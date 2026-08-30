param(
    [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$builder = Join-Path $RepoRoot "asset-catalog/tools/Build-AssetCatalog.ps1"
$validator = Join-Path $RepoRoot "asset-catalog/tools/Validate-AssetCatalog.ps1"
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "Builder nao encontrado." }
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { throw "Validator nao encontrado." }

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("duduq-collision-contract-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

function Write-TextFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function New-Fixture {
    param(
        [string]$Name,
        [hashtable]$Files,
        [object]$Overrides = $null,
        [string]$AliasesCsv = ""
    )

    $root = Join-Path $testRoot $Name
    $images = Join-Path $root "Imagens Ilustrativa"
    $catalog = Join-Path $root "asset-catalog"
    New-Item -ItemType Directory -Path $images -Force | Out-Null
    New-Item -ItemType Directory -Path $catalog -Force | Out-Null

    foreach ($entry in $Files.GetEnumerator()) {
        Write-TextFile -Path (Join-Path $images ([string]$entry.Key)) -Content ([string]$entry.Value)
    }

    $settings = [ordered]@{
        schemaVersion = 2
        repository = "fixture/Assets-DuduQ"
        branch = "test"
        imagesFolder = "Imagens Ilustrativa"
        rawBase = "https://example.invalid/assets/"
        localBase = "/assets/"
        allowedExtensions = @(".png", ".jpg", ".jpeg", ".webp", ".svg")
        semanticFields = @("imageAsset", "imageKey", "imageAssetKey")
        outputField = "imageUrl"
        categoryField = "imageCategory"
        resolutionMetadataField = "_assetResolution"
        writeResolutionMetadata = $true
        fuzzy = [ordered]@{
            enabled = $true
            threshold = 0.92
            minimumMargin = 0.08
            minimumQueryLength = 4
        }
    }
    if ($null -ne $Overrides) {
        $settings.semanticCollisionOverrides = $Overrides
    }

    Write-TextFile -Path (Join-Path $catalog "settings.json") -Content ($settings | ConvertTo-Json -Depth 12)
    if (-not [string]::IsNullOrWhiteSpace($AliasesCsv)) {
        Write-TextFile -Path (Join-Path $catalog "aliases.csv") -Content $AliasesCsv
    }

    return $root
}

function Build-Fixture {
    param([string]$Root)
    & $builder -RepoRoot $Root
    return (([IO.File]::ReadAllText((Join-Path $Root "asset-catalog/assets-index.json"))) | ConvertFrom-Json)
}

function Expect-ValidatorFailure {
    param([string]$Root, [string]$Label)
    $failed = $false
    try {
        & $validator -RepoRoot $Root | Out-Null
    } catch {
        $failed = $true
    }
    if (-not $failed) {
        throw "$Label deveria bloquear o validator, mas passou."
    }
}

function Expect-ValidatorPass {
    param([string]$Root, [string]$Label)
    try {
        & $validator -RepoRoot $Root | Out-Null
    } catch {
        throw "$Label deveria passar o validator: $($_.Exception.Message)"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    # 1 + 7. Colisao sem override permanece visivel e bloqueia CI/validator.
    $root1 = New-Fixture -Name "01-unresolved" -Files @{
        "Bye - tchau.png" = "same-canonical-binary"
        "Bye-tchau.png" = "different-binary"
    }
    $catalog1 = Build-Fixture -Root $root1
    Assert-True (@($catalog1.unresolvedCollisions).Count -eq 1) "Caso 1: colisao sem override nao apareceu em unresolvedCollisions."
    Assert-True (@($catalog1.resolvedCollisions).Count -eq 0) "Caso 1: colisao sem override foi marcada como resolvida."
    Expect-ValidatorFailure -Root $root1 -Label "Caso 1/7: colisao sem override"
    Write-Host "OK 1/7: colisao sem override permanece unresolved e bloqueia CI." -ForegroundColor Green

    # 2 + 6. Override valido usando o asset canonico semanticamente nomeado e byte-equivalente.
    $validOverride = [ordered]@{
        "bye tchau" = [ordered]@{
            canonicalAsset = "greeting-goodbye-tchau.png"
            reason = "canonical greeting asset"
        }
    }
    $root2 = New-Fixture -Name "02-valid-override" -Files @{
        "Bye - tchau.png" = "same-canonical-binary"
        "Bye-tchau.png" = "different-binary"
        "greeting-goodbye-tchau.png" = "same-canonical-binary"
    } -Overrides $validOverride
    $catalog2 = Build-Fixture -Root $root2
    Assert-True (@($catalog2.unresolvedCollisions).Count -eq 0) "Caso 2: override valido ainda deixou colisao unresolved."
    Assert-True (@($catalog2.resolvedCollisions).Count -eq 1) "Caso 2/6: colisao resolvida nao apareceu em resolvedCollisions."
    $resolved2 = @($catalog2.resolvedCollisions)[0]
    Assert-True ([string]$resolved2.status -eq "resolved") "Caso 6: status da colisao nao e resolved."
    Assert-True ([string]$resolved2.canonicalAsset -eq "greeting-goodbye-tchau.png") "Caso 2: asset canonico incorreto."
    Assert-True ([string]$resolved2.participationMode -eq "content-equivalent") "Caso 2: equivalencia binaria nao foi auditada."
    Expect-ValidatorPass -Root $root2 -Label "Caso 2/6: override valido"
    Write-Host "OK 2/6: override valido passa e permanece auditavel como resolved." -ForegroundColor Green

    # 3. Override para arquivo inexistente deve falhar.
    $missingOverride = [ordered]@{
        "bye tchau" = [ordered]@{
            canonicalAsset = "missing.png"
            reason = "invalid test"
        }
    }
    $root3 = New-Fixture -Name "03-missing-canonical" -Files @{
        "Bye - tchau.png" = "a"
        "Bye-tchau.png" = "b"
    } -Overrides $missingOverride
    $catalog3 = Build-Fixture -Root $root3
    Assert-True (@($catalog3.errors).Count -gt 0) "Caso 3: canonicalAsset inexistente nao gerou erro."
    Assert-True (@($catalog3.unresolvedCollisions).Count -eq 1) "Caso 3: override invalido escondeu a colisao."
    Expect-ValidatorFailure -Root $root3 -Label "Caso 3: canonical inexistente"
    Write-Host "OK 3: canonicalAsset inexistente e rejeitado." -ForegroundColor Green

    # 4. Override para asset real, mas sem participacao direta ou equivalencia binaria, deve falhar.
    $outsiderOverride = [ordered]@{
        "bye tchau" = [ordered]@{
            canonicalAsset = "other.png"
            reason = "invalid outsider test"
        }
    }
    $root4 = New-Fixture -Name "04-outsider" -Files @{
        "Bye - tchau.png" = "a"
        "Bye-tchau.png" = "b"
        "other.png" = "not-a-participant"
    } -Overrides $outsiderOverride
    $catalog4 = Build-Fixture -Root $root4
    Assert-True (@($catalog4.errors).Count -gt 0) "Caso 4: asset outsider nao gerou erro."
    Assert-True (@($catalog4.resolvedCollisions).Count -eq 0) "Caso 4: asset outsider resolveu indevidamente a colisao."
    Expect-ValidatorFailure -Root $root4 -Label "Caso 4: asset fora da colisao"
    Write-Host "OK 4: asset que nao participa da colisao e rejeitado." -ForegroundColor Green

    # 5. Alias invalido continua visivel como warning e bloqueia integridade.
    $root5 = New-Fixture -Name "05-invalid-alias" -Files @{
        "dog.png" = "dog"
    } -AliasesCsv "alias,target,category,notes`ndog,missing-dog.png,animals,invalid test`n"
    $catalog5 = Build-Fixture -Root $root5
    Assert-True (@($catalog5.warnings).Count -eq 1) "Caso 5: alias invalido nao gerou exatamente um warning."
    Expect-ValidatorFailure -Root $root5 -Label "Caso 5: alias invalido"
    Write-Host "OK 5: alias invalido permanece warning bloqueante." -ForegroundColor Green

    Write-Host ""
    Write-Host "SEMANTIC COLLISION CONTRACT: 7/7 REGRAS APROVADAS." -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

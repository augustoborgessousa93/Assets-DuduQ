param(
    [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


function Get-PropertyValueSafe {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }

    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]$property.Name -eq $Name) {
            Write-Output -NoEnumerate $property.Value
            return
        }
    }

    return $null
}

function First-OrNull {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Array]) {
        if ($Value.Count -eq 0) { return $null }
        return $Value[0]
    }
    return $Value
}

function Find-AssetsRepo {
    $candidates = @(
        "$env:USERPROFILE\OneDrive\Documentos\GitHub\Assets-DuduQ",
        "$env:USERPROFILE\Documents\GitHub\Assets-DuduQ",
        "$env:USERPROFILE\OneDrive\Documents\GitHub\Assets-DuduQ"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Assets-DuduQ nao encontrado automaticamente."
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Find-AssetsRepo
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$integration = Join-Path $RepoRoot "asset-catalog\integration-b"
$resolver = Join-Path $integration "Resolve-MechanicAssets.ps1"
$sample = Join-Path $integration "ETAPA_B_5_MECANICAS.json"

if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) {
    throw "Resolve-MechanicAssets.ps1 nao encontrado."
}
if (-not (Test-Path -LiteralPath $sample -PathType Leaf)) {
    throw "Sample da Etapa B nao encontrado."
}

$temp = Join-Path $env:TEMP "DuduQ-SmartAssets-Integration-B-SelfTest"
New-Item -ItemType Directory -Path $temp -Force | Out-Null

$output = Join-Path $temp "etapa-b-selftest-output.json"

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver `
        -InputPath $sample `
        -OutputPath $output `
        -RepoRoot $RepoRoot

    if ($LASTEXITCODE -ne 0) {
        throw "Resolver da Etapa B retornou erro no self-test."
    }

    $data = ([IO.File]::ReadAllText($output)) | ConvertFrom-Json
    $reportPath = Join-Path $temp "etapa-b-selftest-output.assets-report.json"

    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "Relatorio QA da Etapa B nao foi criado."
    }

    $qa = ([IO.File]::ReadAllText($reportPath)) | ConvertFrom-Json

    $target = $data.activities[0].questions[0].metadata.targetShooter.items[0]
    $matching = $data.activities[1].questions[0].metadata.matching
    $dragQuestion = $data.activities[2].questions[0]
    $smart = $data.activities[3].questions[0].metadata.smartSentence
    $bubble = $data.activities[4].questions[0].alternatives[0]

    $targetImage = [string](Get-PropertyValueSafe -Object $target -Name "image")

    $matchingAssets = Get-PropertyValueSafe -Object $matching -Name "assets"
    $matchingDog = [string](Get-PropertyValueSafe -Object $matchingAssets -Name "dogScene")
    $matchingCat = [string](Get-PropertyValueSafe -Object $matchingAssets -Name "catScene")

    $dragMetadata = Get-PropertyValueSafe -Object $dragQuestion -Name "metadata"
    $dragConfig = Get-PropertyValueSafe -Object $dragMetadata -Name "dragDrop"
    $dragTargets = Get-PropertyValueSafe -Object $dragConfig -Name "targets"
    $dragTarget = First-OrNull -Value $dragTargets
    $dragTargetImage = Get-PropertyValueSafe -Object $dragTarget -Name "image"
    $dragTargetSrc = [string](Get-PropertyValueSafe -Object $dragTargetImage -Name "src")

    $dragAlternatives = Get-PropertyValueSafe -Object $dragQuestion -Name "alternatives"
    $dragAlternative = First-OrNull -Value $dragAlternatives
    $dragAlternativeImage = Get-PropertyValueSafe -Object $dragAlternative -Name "image"
    $dragAlternativeSrc = [string](Get-PropertyValueSafe -Object $dragAlternativeImage -Name "src")

    $smartImage = [string](Get-PropertyValueSafe -Object $smart -Name "imageSrc")

    $bubbleMetadata = Get-PropertyValueSafe -Object $bubble -Name "metadata"
    $bubbleKey = [string](Get-PropertyValueSafe -Object $bubbleMetadata -Name "imageAssetKey")

    $checks = @()

    $checks += [pscustomobject]@{
        name = "Target Shooter"
        ok = ($targetImage -match "Cachorro\.png")
        detail = $targetImage
    }

    $checks += [pscustomobject]@{
        name = "Matching"
        ok = (
            $matchingDog -match "Cachorro\.png" -and
            $matchingCat -match "Gato\.png"
        )
        detail = ($matchingDog + " | " + $matchingCat)
    }

    $checks += [pscustomobject]@{
        name = "Matching native keys preserved"
        ok = (
            [string]$matching.leftItems[0].imageAssetKey -eq "dogScene" -and
            [string]$matching.rightItems[0].imageAssetKey -eq "catScene"
        )
        detail = (
            [string]$matching.leftItems[0].imageAssetKey +
            " | " +
            [string]$matching.rightItems[0].imageAssetKey
        )
    }

    $checks += [pscustomobject]@{
        name = "QA clean"
        ok = (
            [int]$qa.counts.fallback -eq 0 -and
            [int]$qa.counts.blocked -eq 0
        )
        detail = (
            "fallback=" + [string]$qa.counts.fallback +
            " | blocked=" + [string]$qa.counts.blocked
        )
    }

    $checks += [pscustomobject]@{
        name = "Drag & Drop target"
        ok = ($dragTargetSrc -match "Borracha\.png")
        detail = $dragTargetSrc
    }

    $checks += [pscustomobject]@{
        name = "Drag & Drop alternative"
        ok = ($dragAlternativeSrc -match "Borracha\.png")
        detail = $dragAlternativeSrc
    }

    $checks += [pscustomobject]@{
        name = "Smart Sentence"
        ok = ($smartImage -match "Boy\.png")
        detail = $smartImage
    }

    $checks += [pscustomobject]@{
        name = "Bubble Pop R124 bridge"
        ok = ($bubbleKey -eq "letterA")
        detail = $bubbleKey
    }

    Write-Host ""
    Write-Host "DUDUQ SMART ASSETS - SELF-TEST ETAPA B" -ForegroundColor Cyan

    $failed = 0
    foreach ($check in $checks) {
        if ($check.ok) {
            Write-Host ("[OK] " + $check.name + " -> " + $check.detail) -ForegroundColor Green
        }
        else {
            $failed += 1
            Write-Host ("[FALHOU] " + $check.name + " -> " + $check.detail) -ForegroundColor Red
        }
    }

    if ($failed -gt 0) {
        Write-Host ""
        Write-Host ("Falhas: " + $failed) -ForegroundColor Red
        Write-Host "ETAPA B SELF-TEST: REPROVADA." -ForegroundColor Red
        exit 3
    }

    Write-Host ""
    Write-Host "ETAPA B SELF-TEST: APROVADA." -ForegroundColor Green
}
finally {
    foreach ($file in @(
        $output,
        (Join-Path $temp "etapa-b-selftest-output.assets-report.json")
    )) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
        }
    }
}

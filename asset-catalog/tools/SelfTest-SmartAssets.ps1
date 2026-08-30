param(
    [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Normalize-Key {
    param([object]$Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    try { $text = [Uri]::UnescapeDataString($text) } catch {}
    $text = [IO.Path]::GetFileNameWithoutExtension($text)

    $formD = $text.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder

    foreach ($ch in $formD.ToCharArray()) {
        $unicodeCategory = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($unicodeCategory -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($ch)
        }
    }

    $text = $builder.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
    $text = $text -replace '&', ' e '
    $text = $text -replace '[_\-]+', ' '
    $text = $text -replace '[^\p{L}\p{Nd}]+', ' '
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

function Get-PropertyValue {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Find-AssetsRepo
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$catalogPath = Join-Path $RepoRoot "asset-catalog/assets-index.json"

if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "assets-index.json nao encontrado."
}

$catalog = ([IO.File]::ReadAllText($catalogPath)) | ConvertFrom-Json

if ([int]$catalog.stats.images -lt 1) {
    throw "Catalogo vazio."
}

$globalFallback = Get-PropertyValue -Object $catalog.fallbacks -Name "*"
if ($null -eq $globalFallback) {
    throw "Fallback global nao foi resolvido."
}

$checks = @(
    [pscustomobject]@{ request = "dog"; expectedFile = "pet-dog-cachorro.png" },
    [pscustomobject]@{ request = "eraser"; expectedFile = "Borracha.png" },
    [pscustomobject]@{ request = "goodbye"; expectedFile = "greeting-goodbye-tchau.png" }
)

foreach ($check in $checks) {
    $key = Normalize-Key $check.request

    $assetId = Get-PropertyValue -Object $catalog.aliases -Name $key
    if ($null -eq $assetId) {
        throw ("Alias de teste nao resolvido: " + $check.request)
    }

    $asset = Get-PropertyValue -Object $catalog.assets -Name ([string]$assetId)
    if ($null -eq $asset) {
        throw ("Asset de teste ausente para: " + $check.request)
    }

    if ([string]$asset.file -ne [string]$check.expectedFile) {
        throw (
            "Teste '" + $check.request + "' resolveu para '" +
            [string]$asset.file + "' em vez de '" +
            [string]$check.expectedFile + "'."
        )
    }

    Write-Host (
        "OK: " + $check.request + " -> " + [string]$asset.file
    ) -ForegroundColor Green
}

Write-Host ("OK: fallback global -> " + [string]$globalFallback) -ForegroundColor Green

Write-Host ""
Write-Host "Executando teste end-to-end do Resolve-DuduQContent.ps1..." -ForegroundColor Cyan

$testRoot = Join-Path $RepoRoot "asset-catalog/test"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$testInput = Join-Path $testRoot "__smart-assets-selftest-input.json"
$testOutput = Join-Path $testRoot "__smart-assets-selftest-output.json"
$testReport = Join-Path $testRoot "__smart-assets-selftest-output.assets-report.json"

$testObject = [ordered]@{
    items = @(
        [ordered]@{
            id = "dog"
            imageAsset = "dog"
            imageCategory = "animals"
        },
        [ordered]@{
            id = "eraser"
            imageAsset = "eraser"
            imageCategory = "school"
        },
        [ordered]@{
            id = "unknown"
            imageAsset = "giraffe"
            imageCategory = "animals"
        }
    )
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    $testInput,
    ($testObject | ConvertTo-Json -Depth 10),
    $utf8NoBom
)

try {
    & (Join-Path $RepoRoot "asset-catalog/tools/Resolve-DuduQContent.ps1") -InputPath $testInput -OutputPath $testOutput -RepoRoot $RepoRoot

    if (-not (Test-Path -LiteralPath $testOutput -PathType Leaf)) {
        throw "Arquivo de saida do resolver nao foi criado."
    }

    $resolved = ([IO.File]::ReadAllText($testOutput)) | ConvertFrom-Json

    if ([string]$resolved.items[0]._assetResolution.file -ne "pet-dog-cachorro.png") {
        throw "Self-test dog nao resolveu para pet-dog-cachorro.png."
    }

    if ([string]$resolved.items[1]._assetResolution.file -ne "Borracha.png") {
        throw "Self-test eraser nao resolveu para Borracha.png."
    }

    if ([string]$resolved.items[2]._assetResolution.status -ne "fallback") {
        throw "Self-test de asset ausente nao usou fallback."
    }

    Write-Host "OK: resolver de conteudo end-to-end." -ForegroundColor Green
}
finally {
    foreach ($path in @($testInput, $testOutput, $testReport)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

Write-Host ""
Write-Host "SMART ASSETS SELF-TEST: APROVADO." -ForegroundColor Green

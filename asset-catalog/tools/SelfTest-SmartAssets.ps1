param([string]$RepoRoot = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
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
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
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

function Get-MapValue {
    param([object]$Map,[string]$Key)
    if ($null -eq $Map) { return $null }
    $property = $Map.PSObject.Properties[$Key]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$catalogPath = Join-Path $RepoRoot "asset-catalog\assets-index.json"
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { throw "assets-index.json nao encontrado." }
$catalog = ([IO.File]::ReadAllText($catalogPath)) | ConvertFrom-Json

if ([int]$catalog.schemaVersion -ne 2) { throw "CATALOG_SCHEMA_VERSION != 2" }
if ([int]$catalog.stats.images -lt 1) { throw "CATALOG_IMAGES=0" }
if ([int]$catalog.stats.uniqueKeys -ne [int]$catalog.stats.images) { throw "UNIQUE_KEYS_NOT_COHERENT" }
if ([int]$catalog.stats.unresolvedCollisions -ne 0) { throw "UNRESOLVED_COLLISIONS != 0" }
if ([int]$catalog.stats.warnings -ne 0) { throw "WARNINGS != 0" }
if ([int]$catalog.stats.errors -ne 0) { throw "ERRORS != 0" }

$fallbackId = Get-MapValue -Map $catalog.fallbacks -Key "*"
if (-not $fallbackId) { throw "GLOBAL_FALLBACK_MISSING" }
$fallbackAsset = Get-MapValue -Map $catalog.assets -Key ([string]$fallbackId)
if ($null -eq $fallbackAsset -or [string]$fallbackAsset.file -ne "placeholder-generic-image.svg") {
    throw "GLOBAL_FALLBACK_INCORRECT"
}

$checks = @(
    [pscustomobject]@{ request="dog"; expected="animal-dog-cachorro.png"; group="legacy" },
    [pscustomobject]@{ request="cachorro"; expected="animal-dog-cachorro.png"; group="legacy" },
    [pscustomobject]@{ request="eraser"; expected="school-object-eraser-borracha.png"; group="legacy" },
    [pscustomobject]@{ request="children greeting"; expected="scene-children-greeting.png"; group="legacy" },
    [pscustomobject]@{ request="profile:maya"; expected="character-maya.png"; group="legacy" },
    [pscustomobject]@{ request="profile:maya:10"; expected="character-maya.png"; group="legacy" },
    [pscustomobject]@{ request="profile:ana:12"; expected="character-ana.png"; group="legacy" },
    [pscustomobject]@{ request="duo:maya:leo"; expected="y3-duo-leo-maya-context.png"; group="year3" },
    [pscustomobject]@{ request="duo:leo:maya"; expected="y3-duo-leo-maya-context.png"; group="year3" },
    [pscustomobject]@{ request="duo:leo:mia"; expected="y3-duo-leo-mia-context.png"; group="year3" },
    [pscustomobject]@{ request="green car"; expected="y3-green-car.png"; group="year3" },
    [pscustomobject]@{ request="two green eyes"; expected="y3-two-green-eyes.png"; group="year3" },
    [pscustomobject]@{ request="six blue rectangles"; expected="y3-six-blue-rectangles.png"; group="year3" },
    [pscustomobject]@{ request="20"; expected="number-20-twenty-vinte.png"; group="legacy" },
    [pscustomobject]@{ request="twenty"; expected="number-20-twenty-vinte.png"; group="legacy" },
    [pscustomobject]@{ request="vinte"; expected="number-20-twenty-vinte.png"; group="legacy" },
    [pscustomobject]@{ request="30"; expected="number-30-thirty-trinta.png"; group="new-number" },
    [pscustomobject]@{ request="thirty"; expected="number-30-thirty-trinta.png"; group="new-number" },
    [pscustomobject]@{ request="trinta"; expected="number-30-thirty-trinta.png"; group="new-number" },
    [pscustomobject]@{ request="33"; expected="number-33-thirty-three-trinta-e-tres.png"; group="new-number" },
    [pscustomobject]@{ request="thirty-three"; expected="number-33-thirty-three-trinta-e-tres.png"; group="new-number" },
    [pscustomobject]@{ request="thirty three"; expected="number-33-thirty-three-trinta-e-tres.png"; group="new-number" },
    [pscustomobject]@{ request="trinta e tres"; expected="number-33-thirty-three-trinta-e-tres.png"; group="new-number" },
    [pscustomobject]@{ request="38"; expected="number-38-thirty-eight-trinta-e-oito.png"; group="new-number" },
    [pscustomobject]@{ request="thirty-eight"; expected="number-38-thirty-eight-trinta-e-oito.png"; group="new-number" },
    [pscustomobject]@{ request="thirty eight"; expected="number-38-thirty-eight-trinta-e-oito.png"; group="new-number" },
    [pscustomobject]@{ request="trinta e oito"; expected="number-38-thirty-eight-trinta-e-oito.png"; group="new-number" },
    [pscustomobject]@{ request="40"; expected="number-40-forty-quarenta.png"; group="new-number" },
    [pscustomobject]@{ request="forty"; expected="number-40-forty-quarenta.png"; group="new-number" },
    [pscustomobject]@{ request="quarenta"; expected="number-40-forty-quarenta.png"; group="new-number" }
)

foreach ($check in $checks) {
    $key = Normalize-Key $check.request
    $assetId = Get-MapValue -Map $catalog.aliases -Key $key
    $mode = "ALIAS"
    if (-not $assetId) {
        $assetId = Get-MapValue -Map $catalog.byKey -Key $key
        $mode = "KEY"
    }
    if (-not $assetId) { throw ("SENTINEL_NOT_RESOLVED: " + $check.request) }
    $asset = Get-MapValue -Map $catalog.assets -Key ([string]$assetId)
    if ($null -eq $asset) { throw ("SENTINEL_ASSET_MISSING: " + $check.request) }
    if ([string]$asset.file -ne [string]$check.expected) {
        throw ("SENTINEL_WRONG_TARGET: {0} -> {1}, expected {2}" -f $check.request,[string]$asset.file,[string]$check.expected)
    }
    Write-Host ("OK [{0}] {1} -> {2} [{3}]" -f $check.group,$check.request,[string]$asset.file,$mode) -ForegroundColor Green
}

Write-Host ("OK: fallback global -> " + [string]$fallbackAsset.file) -ForegroundColor Green

$testRoot = Join-Path $RepoRoot "asset-catalog\test"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$inputPath = Join-Path $testRoot "__smart-assets-selftest-input.json"
$outputPath = Join-Path $testRoot "__smart-assets-selftest-output.json"
$reportPath = Join-Path $testRoot "__smart-assets-selftest-output.assets-report.json"

$items = @()
foreach ($check in $checks) {
    $items += [ordered]@{ id=$check.request; imageAsset=$check.request; imageCategory="numbers" }
}
$items += [ordered]@{ id="unknown"; imageAsset="definitely-missing-duduq-asset"; imageCategory="unknown" }
$payload = [ordered]@{ items=$items }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($inputPath,($payload | ConvertTo-Json -Depth 10),$utf8NoBom)

try {
    $resolver = Join-Path $RepoRoot "asset-catalog\tools\Resolve-DuduQContent.ps1"
    & $resolver -InputPath $inputPath -OutputPath $outputPath -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "RESOLVER_OUTPUT_MISSING" }
    $resolved = ([IO.File]::ReadAllText($outputPath)) | ConvertFrom-Json

    for ($i=0; $i -lt $checks.Count; $i++) {
        $meta = $resolved.items[$i]._assetResolution
        if ($null -eq $meta) { throw ("RESOLVER_METADATA_MISSING: " + $checks[$i].request) }
        if ([string]$meta.file -ne [string]$checks[$i].expected) {
            throw ("RESOLVER_WRONG_TARGET: {0} -> {1}" -f $checks[$i].request,[string]$meta.file)
        }
        if ([string]$meta.status -ne "resolved") { throw ("RESOLVER_STATUS_NOT_RESOLVED: " + $checks[$i].request) }
        if ([string]$meta.strategy -notin @("alias","exact")) { throw ("RESOLVER_FORBIDDEN_STRATEGY: {0} -> {1}" -f $checks[$i].request,[string]$meta.strategy) }
    }

    $unknownMeta = $resolved.items[$checks.Count]._assetResolution
    if ([string]$unknownMeta.status -ne "fallback" -or [string]$unknownMeta.file -ne "placeholder-generic-image.svg") {
        throw "FALLBACK_SENTINEL_FAIL"
    }
    Write-Host "END_TO_END_RESOLVER = PASS" -ForegroundColor Green
}
finally {
    foreach ($path in @($inputPath,$outputPath,$reportPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}

Write-Host "LEGACY_SENTINELS = PASS" -ForegroundColor Green
Write-Host "YEAR3_SENTINELS = PASS" -ForegroundColor Green
Write-Host "NEW_NUMBER_SENTINELS = PASS" -ForegroundColor Green
Write-Host "FALLBACK_SENTINEL = PASS" -ForegroundColor Green
Write-Host "SMART ASSETS SELF-TEST: APROVADO." -ForegroundColor Green

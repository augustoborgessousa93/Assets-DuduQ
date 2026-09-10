param(
    [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

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

function Get-PropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$catalogPath = Join-Path $RepoRoot "asset-catalog\assets-index.json"
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "assets-index.json nao encontrado."
}

$catalog = ([IO.File]::ReadAllText($catalogPath)) | ConvertFrom-Json
if ([int]$catalog.stats.images -lt 1) {
    throw "Catalogo vazio."
}

$globalFallbackId = Get-PropertyValue -Object $catalog.fallbacks -Name "*"
if ($null -eq $globalFallbackId) {
    throw "Fallback global nao foi resolvido."
}
$globalFallbackAsset = Get-PropertyValue -Object $catalog.assets -Name ([string]$globalFallbackId)
if ($null -eq $globalFallbackAsset -or [string]$globalFallbackAsset.file -ne "placeholder-generic-image.svg") {
    throw "Fallback global nao aponta para placeholder-generic-image.svg."
}

$checks = @(
    [pscustomobject]@{ request = "dog"; expectedFile = "animal-dog-cachorro.png" },
    [pscustomobject]@{ request = "cachorro"; expectedFile = "animal-dog-cachorro.png" },
    [pscustomobject]@{ request = "eraser"; expectedFile = "school-object-eraser-borracha.png" },
    [pscustomobject]@{ request = "children greeting"; expectedFile = "scene-children-greeting.png" },
    [pscustomobject]@{ request = "profile:maya"; expectedFile = "character-maya.png" },
    [pscustomobject]@{ request = "profile:maya:10"; expectedFile = "character-maya.png" },
    [pscustomobject]@{ request = "profile:ana:12"; expectedFile = "character-ana.png" },
    [pscustomobject]@{ request = "duo:maya:leo"; expectedFile = "y3-duo-leo-maya-context.png" },
    [pscustomobject]@{ request = "duo:leo:maya"; expectedFile = "y3-duo-leo-maya-context.png" },
    [pscustomobject]@{ request = "duo:leo:mia"; expectedFile = "y3-duo-leo-mia-context.png" },
    [pscustomobject]@{ request = "green car"; expectedFile = "y3-green-car.png" },
    [pscustomobject]@{ request = "two green eyes"; expectedFile = "y3-two-green-eyes.png" },
    [pscustomobject]@{ request = "six blue rectangles"; expectedFile = "y3-six-blue-rectangles.png" },
    [pscustomobject]@{ request = "20"; expectedFile = "number-20-twenty-vinte.png" },
    [pscustomobject]@{ request = "twenty"; expectedFile = "number-20-twenty-vinte.png" },
    [pscustomobject]@{ request = "vinte"; expectedFile = "number-20-twenty-vinte.png" }
)

foreach ($check in $checks) {
    $key = Normalize-Key $check.request
    $assetId = Get-PropertyValue -Object $catalog.aliases -Name $key
    $mode = "ALIAS"

    if ($null -eq $assetId) {
        $assetId = Get-PropertyValue -Object $catalog.byKey -Name $key
        $mode = "KEY"
    }

    if ($null -eq $assetId) {
        throw ("Sentinel nao resolveu por KEY/ALIAS: " + $check.request)
    }

    $asset = Get-PropertyValue -Object $catalog.assets -Name ([string]$assetId)
    if ($null -eq $asset) {
        throw ("Asset ausente para sentinel: " + $check.request)
    }

    if ([string]$asset.file -ne [string]$check.expectedFile) {
        throw ("Sentinel '{0}' resolveu para '{1}' em vez de '{2}'." -f $check.request, [string]$asset.file, [string]$check.expectedFile)
    }

    Write-Host ("OK: {0} -> {1} [{2}]" -f $check.request, [string]$asset.file, $mode) -ForegroundColor Green
}

Write-Host ("OK: fallback global -> " + [string]$globalFallbackAsset.file) -ForegroundColor Green
Write-Host ""
Write-Host "Executando teste end-to-end do Resolve-DuduQContent.ps1..." -ForegroundColor Cyan

$testRoot = Join-Path $RepoRoot "asset-catalog\test"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$testInput = Join-Path $testRoot "__smart-assets-selftest-input.json"
$testOutput = Join-Path $testRoot "__smart-assets-selftest-output.json"
$testReport = Join-Path $testRoot "__smart-assets-selftest-output.assets-report.json"

$items = @()
foreach ($check in $checks) {
    $items += [ordered]@{
        id = [string]$check.request
        imageAsset = [string]$check.request
        imageCategory = "test"
    }
}
$items += [ordered]@{
    id = "unknown"
    imageAsset = "__duduq_intentionally_nonexistent_asset_9f31__"
    imageCategory = "test"
}
$testObject = [ordered]@{ items = $items }

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($testInput, ($testObject | ConvertTo-Json -Depth 10), $utf8NoBom)

try {
    $resolver = Join-Path $RepoRoot "asset-catalog\tools\Resolve-DuduQContent.ps1"
    & $resolver -InputPath $testInput -OutputPath $testOutput -RepoRoot $RepoRoot

    if (-not (Test-Path -LiteralPath $testOutput -PathType Leaf)) {
        throw "Arquivo de saida do resolver nao foi criado."
    }

    $resolved = ([IO.File]::ReadAllText($testOutput)) | ConvertFrom-Json

    for ($i = 0; $i -lt $checks.Count; $i++) {
        $resolution = $resolved.items[$i]._assetResolution
        if ($null -eq $resolution) {
            throw ("Metadata de resolucao ausente para: " + $checks[$i].request)
        }
        if ([string]$resolution.file -ne [string]$checks[$i].expectedFile) {
            throw ("Resolver real falhou em '{0}': '{1}'." -f $checks[$i].request, [string]$resolution.file)
        }
        if ([string]$resolution.status -ne "resolved") {
            throw ("Sentinel '{0}' nao ficou resolved." -f $checks[$i].request)
        }
        if ([string]$resolution.strategy -notin @("alias","exact")) {
            throw ("Sentinel '{0}' usou estrategia proibida: {1}" -f $checks[$i].request, [string]$resolution.strategy)
        }
        Write-Host ("RESOLVER: {0} -> {1} [{2}]" -f $checks[$i].request, [string]$resolution.file, ([string]$resolution.strategy).ToUpperInvariant()) -ForegroundColor Green
    }

    $unknown = $resolved.items[$checks.Count]._assetResolution
    if ([string]$unknown.status -ne "fallback") {
        throw "Consulta inexistente nao usou fallback."
    }
    if ([string]$unknown.file -ne "placeholder-generic-image.svg") {
        throw ("Fallback real retornou arquivo incorreto: " + [string]$unknown.file)
    }

    Write-Host "RESOLVER: unknown -> placeholder-generic-image.svg [FALLBACK]" -ForegroundColor Green
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

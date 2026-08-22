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
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    try {
        $text = [Uri]::UnescapeDataString($text)
    } catch {}

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

function Encode-RelativePath {
    param([string]$RelativePath)

    $parts = @($RelativePath -split '/')
    $encodedParts = @()

    foreach ($part in $parts) {
        $encodedParts += [Uri]::EscapeDataString([string]$part)
    }

    return ($encodedParts -join '/')
}

function Find-AssetTarget {
    param(
        [object]$Assets,
        [string]$Target
    )

    $targetText = [string]$Target
    if ([string]::IsNullOrWhiteSpace($targetText)) {
        return @()
    }

    # Explicit enumeration instead of binding Generic.List<T> to object[].
    # This is intentionally conservative for Windows PowerShell 5.1.
    $items = @()
    foreach ($asset in $Assets) {
        $items += $asset
    }

    $pathMatches = @()
    foreach ($asset in $items) {
        if (
            ([string]$asset.path) -ieq $targetText -or
            ([string]$asset.file) -ieq $targetText
        ) {
            $pathMatches += $asset
        }
    }

    if ($pathMatches.Count -gt 0) {
        return @($pathMatches)
    }

    $normalized = Normalize-Key $targetText
    $normalizedMatches = @()

    foreach ($asset in $items) {
        if (([string]$asset.key) -eq $normalized) {
            $normalizedMatches += $asset
        }
    }

    return @($normalizedMatches)
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Find-AssetsRepo
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$catalogRoot = Join-Path $RepoRoot "asset-catalog"
$settingsPath = Join-Path $catalogRoot "settings.json"
$aliasesPath = Join-Path $catalogRoot "aliases.csv"
$fallbacksPath = Join-Path $catalogRoot "fallbacks.csv"

if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "settings.json nao encontrado em $catalogRoot"
}

$settings = ([IO.File]::ReadAllText($settingsPath)) | ConvertFrom-Json
$imagesRoot = Join-Path $RepoRoot ([string]$settings.imagesFolder)

if (-not (Test-Path -LiteralPath $imagesRoot -PathType Container)) {
    throw "Pasta de imagens nao encontrada: $imagesRoot"
}

$allowed = @{}
foreach ($extension in @($settings.allowedExtensions)) {
    $extKey = ([string]$extension).ToLowerInvariant()
    $allowed[$extKey] = $true
}

$assetList = @()
$byNormalized = @{}

$files = @(
    Get-ChildItem -LiteralPath $imagesRoot -File -Recurse |
        Sort-Object FullName
)

foreach ($file in $files) {
    $ext = ([string]$file.Extension).ToLowerInvariant()
    if (-not $allowed.ContainsKey($ext)) {
        continue
    }

    $repoPrefixLength = $RepoRoot.Length
    $imagePrefixLength = $imagesRoot.Length

    $relative = $file.FullName.Substring($repoPrefixLength)
    $relative = $relative.TrimStart([char[]]@([char]92, [char]47)).Replace("\","/")

    $imageRelative = $file.FullName.Substring($imagePrefixLength)
    $imageRelative = $imageRelative.TrimStart([char[]]@([char]92, [char]47)).Replace("\","/")

    $parent = [IO.Path]::GetDirectoryName($imageRelative)
    if ($parent) {
        $parent = $parent.Replace("\","/")
    } else {
        $parent = ""
    }

    $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $key = Normalize-Key $stem
    $encoded = Encode-RelativePath $relative

    $asset = [pscustomobject][ordered]@{
        id = $relative
        file = $file.Name
        stem = $stem
        key = $key
        category = $parent
        path = $relative
        rawUrl = ([string]$settings.rawBase + $encoded)
        localUrl = ([string]$settings.localBase + $encoded)
        sizeBytes = [int64]$file.Length
    }

    $assetList += $asset

    if (-not $byNormalized.ContainsKey($key)) {
        $byNormalized[$key] = @()
    }

    $byNormalized[$key] = @($byNormalized[$key]) + @($relative)
}

$assetsMap = [ordered]@{}
foreach ($asset in $assetList) {
    $assetsMap[[string]$asset.id] = $asset
}

$byKey = [ordered]@{}
$collisions = @()

foreach ($key in @($byNormalized.Keys | Sort-Object)) {
    $ids = @($byNormalized[$key])

    if ($ids.Count -eq 1) {
        $byKey[[string]$key] = [string]$ids[0]
    } else {
        $collisions += [pscustomobject][ordered]@{
            key = [string]$key
            assets = @($ids)
        }
    }
}

$warnings = @()
$aliases = [ordered]@{}

if (Test-Path -LiteralPath $aliasesPath -PathType Leaf) {
    $rows = @(Import-Csv -LiteralPath $aliasesPath -Encoding UTF8)

    foreach ($row in $rows) {
        $aliasKey = Normalize-Key $row.alias
        if (-not $aliasKey) {
            continue
        }

        $matches = @(
            Find-AssetTarget -Assets $assetList -Target ([string]$row.target)
        )

        if ($matches.Count -eq 1) {
            $aliases[[string]$aliasKey] = [string]$matches[0].id
        } elseif ($matches.Count -eq 0) {
            $warnings += "Alias '$($row.alias)' ignorado: target '$($row.target)' nao encontrado."
        } else {
            $warnings += "Alias '$($row.alias)' ignorado: target '$($row.target)' ambiguo."
        }
    }
}

$fallbacks = [ordered]@{}

if (Test-Path -LiteralPath $fallbacksPath -PathType Leaf) {
    $rows = @(Import-Csv -LiteralPath $fallbacksPath -Encoding UTF8)

    foreach ($row in $rows) {
        $category = [string]$row.category

        if ([string]::IsNullOrWhiteSpace($category)) {
            continue
        }

        if ($category -ne "*") {
            $category = Normalize-Key $category
        }

        $matches = @(
            Find-AssetTarget -Assets $assetList -Target ([string]$row.target)
        )

        if ($matches.Count -eq 1) {
            $fallbacks[[string]$category] = [string]$matches[0].id
        } elseif ($matches.Count -eq 0) {
            $warnings += "Fallback '$($row.category)' ignorado: target '$($row.target)' nao encontrado."
        } else {
            $warnings += "Fallback '$($row.category)' ignorado: target '$($row.target)' ambiguo."
        }
    }
}

$catalog = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    repository = [string]$settings.repository
    branch = [string]$settings.branch
    imagesFolder = [string]$settings.imagesFolder
    rawBase = [string]$settings.rawBase
    localBase = [string]$settings.localBase
    semanticFields = @($settings.semanticFields)
    outputField = [string]$settings.outputField
    categoryField = [string]$settings.categoryField
    resolutionMetadataField = [string]$settings.resolutionMetadataField
    writeResolutionMetadata = [bool]$settings.writeResolutionMetadata
    fuzzy = $settings.fuzzy
    stats = [ordered]@{
        images = $assetList.Count
        uniqueKeys = $byKey.Count
        aliases = $aliases.Count
        fallbacks = $fallbacks.Count
        collisions = $collisions.Count
        warnings = $warnings.Count
    }
    assets = $assetsMap
    byKey = $byKey
    aliases = $aliases
    fallbacks = $fallbacks
    collisions = @($collisions)
    warnings = @($warnings)
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$catalogPath = Join-Path $catalogRoot "assets-index.json"
[IO.File]::WriteAllText(
    $catalogPath,
    ($catalog | ConvertTo-Json -Depth 15),
    $utf8NoBom
)

$report = [ordered]@{
    report = "DUDUQ_SMART_ASSETS_CATALOG_BUILD"
    generatedAt = $catalog.generatedAt
    repoRoot = $RepoRoot
    catalogPath = $catalogPath
    stats = $catalog.stats
    collisions = @($collisions)
    warnings = @($warnings)
}

$reportPath = Join-Path $catalogRoot "catalog-build-report.json"
[IO.File]::WriteAllText(
    $reportPath,
    ($report | ConvertTo-Json -Depth 12),
    $utf8NoBom
)

Write-Host ""
Write-Host "DUDUQ SMART ASSETS - CATALOGO ATUALIZADO" -ForegroundColor Green
Write-Host ("Imagens: " + $assetList.Count)
Write-Host ("Chaves unicas: " + $byKey.Count)
Write-Host ("Aliases ativos: " + $aliases.Count)
Write-Host ("Fallbacks ativos: " + $fallbacks.Count)
Write-Host ("Colisoes: " + $collisions.Count)
Write-Host ("Avisos: " + $warnings.Count)
Write-Host ""
Write-Host ("Indice: " + $catalogPath)
Write-Host ("Relatorio: " + $reportPath)

if ($collisions.Count -gt 0) {
    Write-Host ""
    Write-Host "COLISOES DE NOME NORMALIZADO:" -ForegroundColor Yellow
    foreach ($collision in $collisions) {
        Write-Host ("- " + $collision.key + ": " + (@($collision.assets) -join ", ")) -ForegroundColor Yellow
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "AVISOS:" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host ("- " + $warning) -ForegroundColor Yellow
    }
}

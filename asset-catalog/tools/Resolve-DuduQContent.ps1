param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [string]$OutputPath = "",
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

function Get-LevenshteinDistance {
    param(
        [string]$A,
        [string]$B
    )

    if ($A -eq $B) { return 0 }
    if ($A.Length -eq 0) { return $B.Length }
    if ($B.Length -eq 0) { return $A.Length }

    $previous = New-Object 'int[]' ($B.Length + 1)
    $current = New-Object 'int[]' ($B.Length + 1)

    for ($j = 0; $j -le $B.Length; $j++) {
        $previous[$j] = $j
    }

    for ($i = 1; $i -le $A.Length; $i++) {
        $current[0] = $i

        for ($j = 1; $j -le $B.Length; $j++) {
            if ($A[$i - 1] -eq $B[$j - 1]) {
                $cost = 0
            } else {
                $cost = 1
            }

            $delete = $previous[$j] + 1
            $insert = $current[$j - 1] + 1
            $replace = $previous[$j - 1] + $cost

            $minimum = $delete
            if ($insert -lt $minimum) { $minimum = $insert }
            if ($replace -lt $minimum) { $minimum = $replace }

            $current[$j] = $minimum
        }

        $temporary = $previous
        $previous = $current
        $current = $temporary
    }

    return [int]$previous[$B.Length]
}

function Get-Similarity {
    param(
        [string]$A,
        [string]$B
    )

    $maximum = $A.Length
    if ($B.Length -gt $maximum) {
        $maximum = $B.Length
    }

    if ($maximum -eq 0) {
        return [double]1.0
    }

    $distance = Get-LevenshteinDistance -A $A -B $B
    return [double](1.0 - ([double]$distance / [double]$maximum))
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]$property.Name -eq $Name) {
            return $property.Value
        }
    }

    return $null
}

function Set-PropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Object) {
        throw "Nao e possivel definir propriedade em objeto nulo."
    }

    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]$property.Name -eq $Name) {
            $property.Value = $Value
            return
        }
    }

    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
}

function Get-MapValue {
    param(
        [object]$Map,
        [string]$Key
    )

    if ($null -eq $Map) {
        return $null
    }

    foreach ($property in @($Map.PSObject.Properties)) {
        if ([string]$property.Name -eq $Key) {
            return $property.Value
        }
    }

    return $null
}

$InputPath = ([string]$InputPath).Trim().Trim('"')

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Find-AssetsRepo
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$catalogPath = Join-Path $RepoRoot "asset-catalog\assets-index.json"

if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "assets-index.json nao encontrado. Execute ATUALIZAR_CATALOGO.bat primeiro."
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "O caminho informado precisa apontar para um arquivo JSON existente: $InputPath"
}

$InputPath = (Resolve-Path -LiteralPath $InputPath).Path
$catalog = ([IO.File]::ReadAllText($catalogPath)) | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $directory = [IO.Path]::GetDirectoryName($InputPath)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $OutputPath = Join-Path $directory ($baseName + ".resolved.json")
}

$semanticFields = @()
foreach ($field in @($catalog.semanticFields)) {
    $semanticFields += [string]$field
}

$outputField = [string]$catalog.outputField
$categoryField = [string]$catalog.categoryField
$metadataField = [string]$catalog.resolutionMetadataField
$writeMetadata = [bool]$catalog.writeResolutionMetadata

$cache = @{}
$events = @()

function Resolve-Image {
    param(
        [string]$Requested,
        [string]$Category
    )

    $normalized = Normalize-Key $Requested
    $normalizedCategory = Normalize-Key $Category
    $cacheKey = $normalized + "|" + $normalizedCategory

    if ($cache.ContainsKey($cacheKey)) {
        return $cache[$cacheKey]
    }

    $assetId = $null
    $strategy = ""
    $confidence = [double]0.0
    $status = "resolved"

    $aliasId = Get-MapValue -Map $catalog.aliases -Key $normalized

    if ($null -ne $aliasId -and -not [string]::IsNullOrWhiteSpace([string]$aliasId)) {
        $assetId = [string]$aliasId
        $strategy = "alias"
        $confidence = [double]1.0
    }

    if (-not $assetId) {
        $exactId = Get-MapValue -Map $catalog.byKey -Key $normalized

        if ($null -ne $exactId -and -not [string]::IsNullOrWhiteSpace([string]$exactId)) {
            $assetId = [string]$exactId
            $strategy = "exact"
            $confidence = [double]1.0
        }
    }

    if (
        -not $assetId -and
        [bool]$catalog.fuzzy.enabled -and
        $normalized.Length -ge [int]$catalog.fuzzy.minimumQueryLength
    ) {
        $bestKey = ""
        $bestScore = [double]-1.0
        $secondScore = [double]-1.0

        foreach ($property in @($catalog.byKey.PSObject.Properties)) {
            $candidateKey = [string]$property.Name
            $score = Get-Similarity -A $normalized -B $candidateKey

            if ($score -gt $bestScore) {
                $secondScore = $bestScore
                $bestScore = $score
                $bestKey = $candidateKey
            }
            elseif ($score -gt $secondScore) {
                $secondScore = $score
            }
        }

        $threshold = [double]$catalog.fuzzy.threshold
        $minimumMargin = [double]$catalog.fuzzy.minimumMargin

        if (
            $bestScore -ge $threshold -and
            ($bestScore - $secondScore) -ge $minimumMargin
        ) {
            $bestId = Get-MapValue -Map $catalog.byKey -Key $bestKey

            if ($null -ne $bestId) {
                $assetId = [string]$bestId
                $strategy = "fuzzy"
                $confidence = [Math]::Round([double]$bestScore, 4)
            }
        }
    }

    if (-not $assetId -and $normalizedCategory) {
        $categoryFallback = Get-MapValue -Map $catalog.fallbacks -Key $normalizedCategory

        if ($null -ne $categoryFallback -and -not [string]::IsNullOrWhiteSpace([string]$categoryFallback)) {
            $assetId = [string]$categoryFallback
            $strategy = "fallback-category"
            $confidence = [double]0.0
            $status = "fallback"
        }
    }

    if (-not $assetId) {
        $globalFallback = Get-MapValue -Map $catalog.fallbacks -Key "*"

        if ($null -ne $globalFallback -and -not [string]::IsNullOrWhiteSpace([string]$globalFallback)) {
            $assetId = [string]$globalFallback
            $strategy = "fallback-global"
            $confidence = [double]0.0
            $status = "fallback"
        }
    }

    $asset = $null

    if ($assetId) {
        $asset = Get-MapValue -Map $catalog.assets -Key $assetId
    }

    if ($null -eq $asset) {
        $result = [pscustomobject][ordered]@{
            status = "missing"
            requested = $Requested
            normalized = $normalized
            category = $Category
            strategy = "missing"
            confidence = [double]0.0
            assetId = $null
            file = $null
            url = $null
        }
    }
    else {
        $result = [pscustomobject][ordered]@{
            status = $status
            requested = $Requested
            normalized = $normalized
            category = $Category
            strategy = $strategy
            confidence = [double]$confidence
            assetId = [string]$asset.id
            file = [string]$asset.file
            url = [string]$asset.rawUrl
        }
    }

    $cache[$cacheKey] = $result
    return $result
}

function Walk-Node {
    param(
        [object]$Node,
        [string]$Path = '$'
    )

    if ($null -eq $Node) {
        return
    }

    if ($Node -is [System.Array]) {
        for ($index = 0; $index -lt $Node.Count; $index++) {
            Walk-Node -Node $Node[$index] -Path ($Path + "[" + $index + "]")
        }

        return
    }

    if ($Node -isnot [pscustomobject]) {
        return
    }

    $propertyNames = @()

    foreach ($property in @($Node.PSObject.Properties)) {
        $propertyNames += [string]$property.Name
    }

    $semanticFieldUsed = ""
    $requested = ""

    foreach ($fieldName in $semanticFields) {
        $value = Get-PropertyValue -Object $Node -Name $fieldName

        if (
            $value -is [string] -and
            -not [string]::IsNullOrWhiteSpace([string]$value)
        ) {
            $semanticFieldUsed = [string]$fieldName
            $requested = [string]$value
            break
        }
    }

    if ($semanticFieldUsed) {
        $categoryValue = Get-PropertyValue -Object $Node -Name $categoryField
        $category = ""

        if ($null -ne $categoryValue) {
            $category = [string]$categoryValue
        }

        $resolution = Resolve-Image -Requested $requested -Category $category

        if ($resolution.url) {
            Set-PropertyValue -Object $Node -Name $outputField -Value ([string]$resolution.url)
        }

        if ($writeMetadata) {
            Set-PropertyValue -Object $Node -Name $metadataField -Value $resolution
        }

        $event = [pscustomobject][ordered]@{
            path = $Path
            semanticField = $semanticFieldUsed
            requested = $requested
            status = [string]$resolution.status
            strategy = [string]$resolution.strategy
            confidence = [double]$resolution.confidence
            file = $resolution.file
            url = $resolution.url
        }

        $script:events += $event
    }

    foreach ($propertyName in $propertyNames) {
        $child = Get-PropertyValue -Object $Node -Name $propertyName

        if (
            $child -is [pscustomobject] -or
            $child -is [System.Array]
        ) {
            Walk-Node -Node $child -Path ($Path + "." + $propertyName)
        }
    }
}

$contentText = [IO.File]::ReadAllText($InputPath)
$content = $contentText | ConvertFrom-Json

Walk-Node -Node $content

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[IO.File]::WriteAllText(
    $OutputPath,
    ($content | ConvertTo-Json -Depth 50),
    $utf8NoBom
)

$resolvedCount = @($events | Where-Object { $_.status -eq "resolved" }).Count
$fallbackCount = @($events | Where-Object { $_.status -eq "fallback" }).Count
$missingCount = @($events | Where-Object { $_.status -eq "missing" }).Count
$fuzzyCount = @($events | Where-Object { $_.strategy -eq "fuzzy" }).Count

$report = [ordered]@{
    report = "DUDUQ_SMART_ASSETS_CONTENT_RESOLUTION"
    generatedAt = (Get-Date).ToString("o")
    input = $InputPath
    output = $OutputPath
    catalog = $catalogPath
    counts = [ordered]@{
        total = $events.Count
        resolved = $resolvedCount
        fuzzy = $fuzzyCount
        fallback = $fallbackCount
        missing = $missingCount
    }
    events = @($events)
}

$reportDirectory = [IO.Path]::GetDirectoryName($OutputPath)
$reportBase = [IO.Path]::GetFileNameWithoutExtension($OutputPath)
$reportPath = Join-Path $reportDirectory ($reportBase + ".assets-report.json")

[IO.File]::WriteAllText(
    $reportPath,
    ($report | ConvertTo-Json -Depth 20),
    $utf8NoBom
)

Write-Host ""
Write-Host "DUDUQ SMART ASSETS - CONTEUDO RESOLVIDO" -ForegroundColor Green
Write-Host ("Total: " + $events.Count)
Write-Host ("Resolvidos: " + $resolvedCount)
Write-Host ("Fuzzy: " + $fuzzyCount)
Write-Host ("Fallbacks: " + $fallbackCount)
Write-Host ("Missing sem fallback: " + $missingCount)
Write-Host ""
Write-Host ("Saida: " + $OutputPath)
Write-Host ("QA: " + $reportPath)

if ($fallbackCount -gt 0 -or $missingCount -gt 0) {
    Write-Host ""
    Write-Host "ATENCAO: revise o relatorio de QA antes de publicar o lote." -ForegroundColor Yellow
}

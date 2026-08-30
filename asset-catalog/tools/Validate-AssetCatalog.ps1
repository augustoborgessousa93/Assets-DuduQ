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

function Get-PhysicalPath {
    param([string]$Root, [string]$AssetId)
    return (Join-Path $Root ($AssetId -replace '/', [IO.Path]::DirectorySeparatorChar))
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Find-AssetsRepo
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$catalogPath = Join-Path $RepoRoot "asset-catalog/assets-index.json"
$settingsPath = Join-Path $RepoRoot "asset-catalog/settings.json"

if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "assets-index.json nao encontrado."
}
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "settings.json nao encontrado."
}

$catalog = ([IO.File]::ReadAllText($catalogPath)) | ConvertFrom-Json
$settings = ([IO.File]::ReadAllText($settingsPath)) | ConvertFrom-Json

if ([int]$catalog.schemaVersion -lt 2) {
    throw "Catalogo usa schemaVersion antigo: $($catalog.schemaVersion)."
}

$warnings = @(Get-PropertyValue -Object $catalog -Name "warnings")
$errors = @(Get-PropertyValue -Object $catalog -Name "errors")
$unresolved = @(Get-PropertyValue -Object $catalog -Name "unresolvedCollisions")
$resolved = @(Get-PropertyValue -Object $catalog -Name "resolvedCollisions")

if ($warnings.Count -gt 0) {
    throw "Catalogo possui $($warnings.Count) warning(s): $($warnings -join ' | ')"
}
if ($errors.Count -gt 0) {
    throw "Catalogo possui $($errors.Count) erro(s) de configuracao: $($errors -join ' | ')"
}
if ($unresolved.Count -gt 0) {
    throw "Catalogo possui $($unresolved.Count) colisao(oes) semantica(s) nao resolvida(s)."
}

$assets = Get-PropertyValue -Object $catalog -Name "assets"
if ($null -eq $assets) { throw "Mapa assets ausente." }
$assetProperties = @($assets.PSObject.Properties)
if ($assetProperties.Count -ne [int]$catalog.stats.images) {
    throw "Quantidade de IDs de asset difere de stats.images."
}

$seenIds = @{}
foreach ($property in $assetProperties) {
    $id = [string]$property.Name
    if ($seenIds.ContainsKey($id)) {
        throw "ID duplicado no catalogo: $id"
    }
    $seenIds[$id] = $true

    $asset = $property.Value
    if ([string]$asset.id -ne $id) {
        throw "Asset '$id' possui id interno divergente '$($asset.id)'."
    }

    $physicalPath = Get-PhysicalPath -Root $RepoRoot -AssetId $id
    if (-not (Test-Path -LiteralPath $physicalPath -PathType Leaf)) {
        throw "Asset fisico ausente: $id"
    }
}

foreach ($mapName in @("byKey", "aliases", "fallbacks")) {
    $map = Get-PropertyValue -Object $catalog -Name $mapName
    if ($null -eq $map) { throw "Mapa '$mapName' ausente." }
    foreach ($property in @($map.PSObject.Properties)) {
        $targetId = [string]$property.Value
        if (-not $seenIds.ContainsKey($targetId)) {
            throw "Mapa '$mapName' aponta para ID inexistente '$targetId' na chave '$($property.Name)'."
        }
    }
}

foreach ($collision in $resolved) {
    if ([string]$collision.status -ne "resolved") {
        throw "Colisao em resolvedCollisions sem status resolved: $($collision.key)"
    }

    $canonicalId = [string]$collision.canonicalAssetId
    $participants = @($collision.assets | ForEach-Object { [string]$_ })
    $mode = [string]$collision.participationMode
    $equivalentId = [string]$collision.equivalentParticipantId

    if (-not $seenIds.ContainsKey($canonicalId)) {
        throw "Colisao resolvida '$($collision.key)' aponta para ID ausente '$canonicalId'."
    }
    if ($participants -notcontains $equivalentId) {
        throw "Colisao resolvida '$($collision.key)' nao registra participante equivalente valido."
    }

    if ($mode -eq "direct") {
        if ($canonicalId -ne $equivalentId -or $participants -notcontains $canonicalId) {
            throw "Colisao '$($collision.key)' marcou participacao direta de forma inconsistente."
        }
    } elseif ($mode -eq "content-equivalent") {
        $canonicalPath = Get-PhysicalPath -Root $RepoRoot -AssetId $canonicalId
        $participantPath = Get-PhysicalPath -Root $RepoRoot -AssetId $equivalentId
        $canonicalHash = (Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $participantHash = (Get-FileHash -LiteralPath $participantPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($canonicalHash -ne $participantHash) {
            throw "Colisao '$($collision.key)' declara equivalencia binaria que nao existe."
        }
        if ([string]$collision.contentSha256 -ne $canonicalHash) {
            throw "Colisao '$($collision.key)' possui SHA-256 de auditoria divergente."
        }
    } else {
        throw "Colisao '$($collision.key)' possui participationMode desconhecido '$mode'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$collision.reason)) {
        throw "Colisao resolvida '$($collision.key)' nao registra justificativa editorial."
    }
}

$overrideSource = Get-PropertyValue -Object $settings -Name "semanticCollisionOverrides"
if ($null -ne $overrideSource) {
    foreach ($property in @($overrideSource.PSObject.Properties)) {
        $canonicalTarget = [string](Get-PropertyValue -Object $property.Value -Name "canonicalAsset")
        if ([string]::IsNullOrWhiteSpace($canonicalTarget)) {
            throw "Override '$($property.Name)' sem canonicalAsset."
        }
        $normalizedKey = Normalize-Key $property.Name
        $matchingResolved = @($resolved | Where-Object { [string]$_.key -eq $normalizedKey })
        if ($matchingResolved.Count -ne 1) {
            throw "Override '$($property.Name)' nao aparece exatamente uma vez em resolvedCollisions."
        }
    }
}

Write-Host "CANONICAL ASSET CATALOG INTEGRITY: APROVADO." -ForegroundColor Green
Write-Host ("Assets fisicos: " + $assetProperties.Count)
Write-Host ("Colisoes resolvidas: " + $resolved.Count)
Write-Host "Colisoes nao resolvidas: 0"
Write-Host "Warnings: 0"
Write-Host "Erros: 0"

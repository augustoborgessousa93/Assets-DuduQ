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

    $physicalPath = Join-Path $RepoRoot ($id -replace '/', [IO.Path]::DirectorySeparatorChar)
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
    if (-not $seenIds.ContainsKey($canonicalId)) {
        throw "Colisao resolvida '$($collision.key)' aponta para ID ausente '$canonicalId'."
    }
    if ($participants -notcontains $canonicalId) {
        throw "Colisao resolvida '$($collision.key)' aponta para asset que nao participa da colisao."
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
        $matchingResolved = @($resolved | Where-Object { [string]$_.key -eq [string]$property.Name })
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

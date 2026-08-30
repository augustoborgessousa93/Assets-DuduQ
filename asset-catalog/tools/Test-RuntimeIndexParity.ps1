param(
    [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$catalogPath = Join-Path $RepoRoot "asset-catalog/assets-index.json"
$runtimePath = Join-Path $RepoRoot "asset-catalog/runtime-index.js"

if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { throw "assets-index.json missing." }
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw "runtime-index.js missing." }

$catalogJson = [IO.File]::ReadAllText($catalogPath).Trim()
$runtime = [IO.File]::ReadAllText($runtimePath)
$startMarker = "/*__DUDUQ_CATALOG_JSON_START__*/"
$endMarker = "/*__DUDUQ_CATALOG_JSON_END__*/"
$start = $runtime.IndexOf($startMarker, [StringComparison]::Ordinal)
$end = $runtime.IndexOf($endMarker, [StringComparison]::Ordinal)

if ($start -lt 0 -or $end -lt 0 -or $end -le $start) {
    throw "Runtime index provenance markers are missing or malformed."
}

$payloadStart = $start + $startMarker.Length
$runtimeJson = $runtime.Substring($payloadStart, $end - $payloadStart).Trim()
if ($runtimeJson -cne $catalogJson) {
    throw "runtime-index.js payload diverges from assets-index.json. Rebuild; do not edit generated runtime manually."
}

$catalog = $catalogJson | ConvertFrom-Json
if ([int]$catalog.schemaVersion -ne 2) { throw "Runtime parity requires schemaVersion 2." }
if ([int]$catalog.stats.unresolvedCollisions -ne 0) { throw "Runtime parity found unresolved collisions." }
if ([int]$catalog.stats.warnings -ne 0 -or [int]$catalog.stats.errors -ne 0) { throw "Runtime parity found warnings/errors." }

Write-Host "DUDUQ CANONICAL RUNTIME PARITY: APROVADO." -ForegroundColor Green
Write-Host ("Schema: " + $catalog.schemaVersion)
Write-Host ("Assets: " + $catalog.stats.images)
Write-Host ("Aliases: " + $catalog.stats.aliases)
Write-Host ("Resolved collisions: " + $catalog.stats.resolvedCollisions)

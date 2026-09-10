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

if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "Canonical assets-index.json not found. Run Build-AssetCatalog.ps1 first."
}

$catalogJson = [IO.File]::ReadAllText($catalogPath).Trim()
$catalog = $catalogJson | ConvertFrom-Json

if ([int]$catalog.schemaVersion -ne 2) {
    throw "Runtime index requires canonical schemaVersion 2."
}
if ([int]$catalog.stats.unresolvedCollisions -ne 0) {
    throw "Runtime index cannot be generated with unresolved semantic collisions."
}
if ([int]$catalog.stats.warnings -ne 0 -or [int]$catalog.stats.errors -ne 0) {
    throw "Runtime index cannot be generated from a catalog with warnings/errors."
}

$runtime = @"
/* =========================================================
   DUDUQ CANONICAL ASSET CATALOG — RUNTIME INDEX
   AUTO-GENERATED from asset-catalog/assets-index.json.
   DO NOT EDIT BY HAND. Rebuild through the canonical catalog pipeline.
   ========================================================= */
(function (root) {
  "use strict";

  const catalog = /*__DUDUQ_CATALOG_JSON_START__*/$catalogJson/*__DUDUQ_CATALOG_JSON_END__*/;

  function deepFreeze(value) {
    if (!value || typeof value !== "object" || Object.isFrozen(value)) return value;
    Object.getOwnPropertyNames(value).forEach(function (key) {
      deepFreeze(value[key]);
    });
    return Object.freeze(value);
  }

  const frozenCatalog = deepFreeze(catalog);

  if (root.DUDUQ_CANONICAL_ASSET_CATALOG && root.DUDUQ_CANONICAL_ASSET_CATALOG !== frozenCatalog) {
    throw new Error("DUDUQ canonical asset catalog already installed with a different runtime payload.");
  }

  if (!root.DUDUQ_CANONICAL_ASSET_CATALOG) {
    Object.defineProperty(root, "DUDUQ_CANONICAL_ASSET_CATALOG", {
      value: frozenCatalog,
      writable: false,
      configurable: false,
      enumerable: false
    });
  }
})(typeof globalThis !== "undefined" ? globalThis : window);
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($runtimePath, $runtime, $utf8NoBom)

Write-Host "DUDUQ CANONICAL ASSET RUNTIME INDEX: GERADO." -ForegroundColor Green
Write-Host ("Schema: " + $catalog.schemaVersion)
Write-Host ("Assets: " + $catalog.stats.images)
Write-Host ("Aliases: " + $catalog.stats.aliases)
Write-Host ("Runtime: " + $runtimePath)

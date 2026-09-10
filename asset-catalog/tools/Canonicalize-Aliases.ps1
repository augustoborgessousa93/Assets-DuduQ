param([string]$RepoRoot = "")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
$aliasesPath = Join-Path $RepoRoot "asset-catalog\aliases.csv"
$imagesRoot = Join-Path $RepoRoot "Imagens Ilustrativa"

function Normalize-Key([object]$Value) {
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return "" }
  try { $text = [Uri]::UnescapeDataString($text) } catch {}
  $text = [IO.Path]::GetFileNameWithoutExtension($text)
  $formD = $text.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $formD.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) } }
  $text = $sb.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
  $text = $text -replace '&',' e ' -replace '[_\-]+',' ' -replace '[^\p{L}\p{Nd}]+',' ' -replace '\s+',' '
  return $text.Trim()
}

if (-not (Test-Path -LiteralPath $aliasesPath -PathType Leaf)) { throw "aliases.csv nao encontrado." }
if (-not (Test-Path -LiteralPath $imagesRoot -PathType Container)) { throw "Imagens Ilustrativa nao encontrada." }
$byAlias = [ordered]@{}
foreach ($row in @(Import-Csv -LiteralPath $aliasesPath -Encoding UTF8)) {
  $key = Normalize-Key $row.alias
  if (-not $key) { continue }
  if ($byAlias.Contains($key) -and [string]$byAlias[$key].target -ne [string]$row.target) { throw ("ALIAS_COLLISION_EXISTING: " + $key) }
  if (-not $byAlias.Contains($key)) { $byAlias[$key] = [pscustomobject][ordered]@{alias=[string]$row.alias;target=[string]$row.target;category=[string]$row.category;notes=[string]$row.notes} }
}
function Add-Alias([string]$Alias,[string]$Target) {
  $key = Normalize-Key $Alias
  if (-not $key) { return }
  if ($byAlias.Contains($key)) {
    if ([string]$byAlias[$key].target -ne $Target) { throw ("ALIAS_COLLISION_NEW: {0} -> {1} versus {2}" -f $key,[string]$byAlias[$key].target,$Target) }
    return
  }
  $byAlias[$key] = [pscustomobject][ordered]@{alias=$Alias;target=$Target;category='numbers';notes='Canonical number alias'}
}

$numbers = @(
  @(21,'twenty-one','vinte e um','vinte-e-um'), @(22,'twenty-two','vinte e dois','vinte-e-dois'),
  @(23,'twenty-three','vinte e tres','vinte-e-tres'), @(24,'twenty-four','vinte e quatro','vinte-e-quatro'),
  @(25,'twenty-five','vinte e cinco','vinte-e-cinco'), @(26,'twenty-six','vinte e seis','vinte-e-seis'),
  @(27,'twenty-seven','vinte e sete','vinte-e-sete'), @(28,'twenty-eight','vinte e oito','vinte-e-oito'),
  @(29,'twenty-nine','vinte e nove','vinte-e-nove'), @(30,'thirty','trinta','trinta'),
  @(31,'thirty-one','trinta e um','trinta-e-um'), @(32,'thirty-two','trinta e dois','trinta-e-dois'),
  @(33,'thirty-three','trinta e tres','trinta-e-tres'), @(34,'thirty-four','trinta e quatro','trinta-e-quatro'),
  @(35,'thirty-five','trinta e cinco','trinta-e-cinco'), @(36,'thirty-six','trinta e seis','trinta-e-seis'),
  @(37,'thirty-seven','trinta e sete','trinta-e-sete'), @(38,'thirty-eight','trinta e oito','trinta-e-oito'),
  @(39,'thirty-nine','trinta e nove','trinta-e-nove'), @(40,'forty','quarenta','quarenta')
)
foreach ($entry in $numbers) {
  $n=[int]$entry[0]; $en=[string]$entry[1]; $pt=[string]$entry[2]; $ptSlug=[string]$entry[3]
  $target = ('number-{0:D2}-{1}-{2}.png' -f $n,$en,$ptSlug)
  if (-not (Test-Path -LiteralPath (Join-Path $imagesRoot $target) -PathType Leaf)) { throw ("NUMBER_TARGET_MISSING: " + $target) }
  Add-Alias ([string]$n) $target
  Add-Alias $en $target
  Add-Alias $pt $target
}

$missing=@()
foreach ($entry in @($byAlias.Values)) { if (-not (Test-Path -LiteralPath (Join-Path $imagesRoot ([string]$entry.target)) -PathType Leaf)) { $missing += $entry } }
Write-Host ("ALIAS_TARGETS_TOTAL = " + $byAlias.Count)
Write-Host ("ALIAS_TARGETS_MISSING = " + $missing.Count)
if ($missing.Count -gt 0) { foreach($m in $missing){ Write-Host ("MISSING: {0} -> {1}" -f $m.alias,$m.target) -ForegroundColor Red }; throw "ALL_TARGETS_EXIST = FAIL" }
$rowsOut=@($byAlias.Values | Sort-Object { Normalize-Key $_.alias })
$rowsOut | Export-Csv -LiteralPath $aliasesPath -NoTypeInformation -Encoding UTF8
$written=@(Import-Csv -LiteralPath $aliasesPath -Encoding UTF8)
$dupes=@($written | Group-Object { Normalize-Key $_.alias } | Where-Object { $_.Count -gt 1 })
if ($dupes.Count -gt 0) { throw "ALIASES_UNIQUE_AFTER_NORMALIZATION = FAIL" }
Write-Host ("ALIASES_MIGRATED = " + $written.Count)
Write-Host "ALIASES_UNIQUE_AFTER_NORMALIZATION = PASS"
Write-Host "ALL_TARGETS_EXIST = PASS"

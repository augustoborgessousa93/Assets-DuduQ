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
    param([object]$Map, [string]$Key)
    if ($null -eq $Map) { return $null }
    foreach ($property in @($Map.PSObject.Properties)) {
        if ([string]$property.Name -eq $Key) { return $property.Value }
    }
    return $null
}

function Get-LevenshteinDistance {
    param([string]$A, [string]$B)
    if ($A -eq $B) { return 0 }
    if ($A.Length -eq 0) { return $B.Length }
    if ($B.Length -eq 0) { return $A.Length }
    $previous = New-Object 'int[]' ($B.Length + 1)
    $current = New-Object 'int[]' ($B.Length + 1)
    for ($j = 0; $j -le $B.Length; $j++) { $previous[$j] = $j }
    for ($i = 1; $i -le $A.Length; $i++) {
        $current[0] = $i
        for ($j = 1; $j -le $B.Length; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min([Math]::Min($previous[$j] + 1, $current[$j - 1] + 1), $previous[$j - 1] + $cost)
        }
        $temporary = $previous; $previous = $current; $current = $temporary
    }
    return [int]$previous[$B.Length]
}

function Get-Similarity {
    param([string]$A, [string]$B)
    $maximum = [Math]::Max($A.Length, $B.Length)
    if ($maximum -eq 0) { return [double]1.0 }
    return [double](1.0 - ([double](Get-LevenshteinDistance -A $A -B $B) / [double]$maximum))
}

$catalogPath = Join-Path $RepoRoot "asset-catalog/assets-index.json"
$catalog = ([IO.File]::ReadAllText($catalogPath)) | ConvertFrom-Json

if ([int]$catalog.schemaVersion -ne 2) { throw "Core compatibility requires canonical asset schema 2." }
if ([int]$catalog.stats.unresolvedCollisions -ne 0) { throw "Core compatibility cannot run with unresolved semantic collisions." }
if ([int]$catalog.stats.errors -ne 0) { throw "Core compatibility cannot run with catalog configuration errors." }

function Resolve-CanonicalId {
    param([string]$Requested)
    $normalized = Normalize-Key $Requested
    if (-not $normalized) { return $null }

    $aliasId = Get-MapValue -Map $catalog.aliases -Key $normalized
    if ($aliasId) { return [pscustomobject]@{ id = [string]$aliasId; strategy = "alias"; normalized = $normalized } }

    $exactId = Get-MapValue -Map $catalog.byKey -Key $normalized
    if ($exactId) { return [pscustomobject]@{ id = [string]$exactId; strategy = "exact"; normalized = $normalized } }

    if ([bool]$catalog.fuzzy.enabled -and $normalized.Length -ge [int]$catalog.fuzzy.minimumQueryLength) {
        $bestKey = ""
        $bestScore = [double]-1
        $secondScore = [double]-1
        foreach ($property in @($catalog.byKey.PSObject.Properties)) {
            $candidateKey = [string]$property.Name
            $score = Get-Similarity -A $normalized -B $candidateKey
            if ($score -gt $bestScore) {
                $secondScore = $bestScore
                $bestScore = $score
                $bestKey = $candidateKey
            } elseif ($score -gt $secondScore) {
                $secondScore = $score
            }
        }
        if ($bestScore -ge [double]$catalog.fuzzy.threshold -and ($bestScore - $secondScore) -ge [double]$catalog.fuzzy.minimumMargin) {
            $bestId = Get-MapValue -Map $catalog.byKey -Key $bestKey
            if ($bestId) { return [pscustomobject]@{ id = [string]$bestId; strategy = "fuzzy"; normalized = $normalized } }
        }
    }

    return $null
}

# Public semantic forms already supported by Core 1.0.9. These are a regression
# fixture, not a runtime catalog. The canonical repository owns their mapping.
$required = @(
    "1","one","um","number one","number 1","numero um","numero 1",
    "2","two","dois","number two","number 2","numero dois","numero 2",
    "3","three","tres","number three","number 3","numero tres","numero 3",
    "4","four","quatro","number four","number 4","numero quatro","numero 4",
    "5","five","cinco","number five","number 5","numero cinco","numero 5",
    "6","six","seis","number six","number 6","numero seis","numero 6",
    "7","seven","sete","number seven","number 7","numero sete","numero 7",
    "8","eight","oito","number eight","number 8","numero oito","numero 8",
    "9","nine","nove","number nine","number 9","numero nove","numero 9",
    "10","ten","dez","number ten","number 10","numero dez","numero 10",
    "red","vermelho","vermelha","cor vermelha","blue","azul","cor azul",
    "yellow","amarelo","amarela","cor amarela","green","verde","cor verde",
    "orange","laranja","cor laranja","pink","rosa","cor rosa","black","preto","preta","cor preta",
    "white","branco","branca","cor branca","brown","marrom","cor marrom",
    "hello","hi","oi","ola","goodbye","bye","see you","tchau",
    "good morning","bom dia","good afternoon","boa tarde","good night","boa noite",
    "my name","meu nome","what is your name","boy","menino","girl","menina",
    "pencil","lapis","blue pencil","lapis azul","red pencil","lapis vermelho","ruler","regua",
    "eraser","borracha","backpack","school bag","mochila","pencil case","estojo","blue pen","caneta azul",
    "orange crayon","giz de cera laranja","red crayon","giz de cera vermelho",
    "sit down","sentar","sentado","sentada","stand up","em pe","levantar","quiet","silence","silencio",
    "hands","touch hands","maos","tocar as maos","head","touch head","cabeca","tocar a cabeca",
    "arms","touch arms","bracos","tocar os bracos","knees","touch knees","joelhos","tocar os joelhos",
    "feet","touch feet","pes","tocar os pes",
    "dog","cachorro","cat","gato","rabbit","bunny","coelho","turtle","tartaruga","fish","peixe","hamster","hamister","bird","passaro",
    "wake up","waking up","acordar","acordando","brush teeth","brushing teeth","escovar os dentes",
    "go to school","going to school","ir para a escola","have lunch","having lunch","almocar","almocando",
    "play","playing","brincar","brincando","read","reading","ler","lendo","draw","drawing","desenhar","desenhando",
    "rest","resting","descansar","descansando","go to sleep","going to sleep","ir dormir"
)

$failures = @()
$strategyCounts = [ordered]@{ alias = 0; exact = 0; fuzzy = 0 }
foreach ($query in $required) {
    $resolved = Resolve-CanonicalId -Requested $query
    if ($null -eq $resolved) {
        $failures += [pscustomobject]@{ query = $query; normalized = (Normalize-Key $query); reason = "not-resolved-before-fallback" }
        continue
    }
    $strategyCounts[$resolved.strategy] = [int]$strategyCounts[$resolved.strategy] + 1
}

$critical = [ordered]@{
    "bye tchau" = "Imagens Ilustrativa/greeting-goodbye-tchau.png"
    "goodbye" = "Imagens Ilustrativa/greeting-goodbye-tchau.png"
    "dog" = "Imagens Ilustrativa/pet-dog-cachorro.png"
}
foreach ($query in @($critical.Keys)) {
    $resolved = Resolve-CanonicalId -Requested ([string]$query)
    if ($null -eq $resolved -or [string]$resolved.id -ne [string]$critical[$query]) {
        $failures += [pscustomobject]@{
            query = [string]$query
            normalized = (Normalize-Key $query)
            reason = "wrong-canonical-target"
            expected = [string]$critical[$query]
            actual = if ($null -eq $resolved) { $null } else { [string]$resolved.id }
        }
    }
}

$result = [ordered]@{
    contract = "DUDUQ_CORE_1_0_9_ALIAS_COMPATIBILITY"
    requiredQueries = $required.Count
    resolvedQueries = $required.Count - $failures.Count
    strategies = $strategyCounts
    failures = @($failures)
}
$result | ConvertTo-Json -Depth 8

if ($failures.Count -gt 0) {
    throw "Canonical catalog regresses $($failures.Count) Core 1.0.9 semantic queries. Add mappings to Assets-DuduQ, not to a future Core release."
}

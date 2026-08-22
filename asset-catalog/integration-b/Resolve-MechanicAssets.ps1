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

function Get-PropertyValue {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }

    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]$property.Name -eq $Name) {
            # PowerShell 5.1 enumera arrays devolvidos por funcoes.
            # -NoEnumerate preserva inclusive arrays com apenas 1 item.
            Write-Output -NoEnumerate $property.Value
            return
        }
    }

    return $null
}

function Has-Property {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $false }

    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]$property.Name -eq $Name) {
            return $true
        }
    }

    return $false
}

function Set-PropertyValue {
    param([object]$Object, [string]$Name, [object]$Value)

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

function Remove-PropertyValue {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return }

    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]$property.Name -eq $Name) {
            $Object.PSObject.Properties.Remove($Name)
            return
        }
    }
}

function Mask-NativeImageAssetKeys {
    param([object]$Node)

    if ($null -eq $Node) { return }

    if ($Node -is [System.Array]) {
        for ($i = 0; $i -lt $Node.Count; $i++) {
            Mask-NativeImageAssetKeys -Node $Node[$i]
        }
        return
    }

    if ($Node -isnot [pscustomobject]) { return }

    if (Has-Property -Object $Node -Name "imageAssetKey") {
        $nativeValue = Get-PropertyValue -Object $Node -Name "imageAssetKey"
        Set-PropertyValue -Object $Node -Name "__duduqNativeImageAssetKey" -Value $nativeValue
        Remove-PropertyValue -Object $Node -Name "imageAssetKey"
    }

    $names = @()
    foreach ($property in @($Node.PSObject.Properties)) {
        $names += [string]$property.Name
    }

    foreach ($name in $names) {
        if ($name -eq "__duduqNativeImageAssetKey") { continue }
        $child = Get-PropertyValue -Object $Node -Name $name
        if ($child -is [pscustomobject] -or $child -is [System.Array]) {
            Mask-NativeImageAssetKeys -Node $child
        }
    }
}

function Restore-NativeImageAssetKeys {
    param([object]$Node)

    if ($null -eq $Node) { return }

    if ($Node -is [System.Array]) {
        for ($i = 0; $i -lt $Node.Count; $i++) {
            Restore-NativeImageAssetKeys -Node $Node[$i]
        }
        return
    }

    if ($Node -isnot [pscustomobject]) { return }

    if (Has-Property -Object $Node -Name "__duduqNativeImageAssetKey") {
        $nativeValue = Get-PropertyValue -Object $Node -Name "__duduqNativeImageAssetKey"
        Set-PropertyValue -Object $Node -Name "imageAssetKey" -Value $nativeValue
        Remove-PropertyValue -Object $Node -Name "__duduqNativeImageAssetKey"
    }

    $names = @()
    foreach ($property in @($Node.PSObject.Properties)) {
        $names += [string]$property.Name
    }

    foreach ($name in $names) {
        $child = Get-PropertyValue -Object $Node -Name $name
        if ($child -is [pscustomobject] -or $child -is [System.Array]) {
            Restore-NativeImageAssetKeys -Node $child
        }
    }
}

function Ensure-ObjectProperty {
    param([object]$Object, [string]$Name)

    $current = Get-PropertyValue -Object $Object -Name $Name

    if ($current -is [pscustomobject]) {
        return $current
    }

    $created = [pscustomobject][ordered]@{}
    Set-PropertyValue -Object $Object -Name $Name -Value $created
    return $created
}

function Normalize-Key {
    param([object]$Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    $formD = $text.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder

    foreach ($ch in $formD.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($ch)
        }
    }

    $text = $builder.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
    $text = $text -replace '[_\-]+', ' '
    $text = $text -replace '[^\p{L}\p{Nd}]+', ' '
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

$InputPath = ([string]$InputPath).Trim().Trim('"')

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Find-AssetsRepo
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "O caminho precisa apontar para um JSON existente: $InputPath"
}

$InputPath = (Resolve-Path -LiteralPath $InputPath).Path

$semanticResolver = Join-Path $RepoRoot "asset-catalog\tools\Resolve-DuduQContent.ps1"
$compatPath = Join-Path $RepoRoot "asset-catalog\integration-b\bubble-pop-compat.json"

if (-not (Test-Path -LiteralPath $semanticResolver -PathType Leaf)) {
    throw "Resolver Smart Assets nao encontrado. Repare/instale o Smart Assets V1.3 primeiro."
}

if (-not (Test-Path -LiteralPath $compatPath -PathType Leaf)) {
    throw "Integracao B nao instalada: bubble-pop-compat.json ausente."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDir = [IO.Path]::GetDirectoryName($InputPath)
    $outputBase = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $OutputPath = Join-Path $outputDir ($outputBase + ".mechanics.resolved.json")
}

$tempDir = Join-Path $env:TEMP "DuduQ-SmartAssets-Integration-B"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$tempId = [Guid]::NewGuid().ToString("N")
$tempInput = Join-Path $tempDir ("semantic-input-" + $tempId + ".json")
$tempResolved = Join-Path $tempDir ("semantic-output-" + $tempId + ".json")

try {
    # Etapa B usa imageAsset como fonte semantica.
    # imageAssetKey ja e contrato NATIVO de varias mecanicas R124.
    # Se ele for enviado diretamente ao resolver V1.3, pode ser confundido
    # com um pedido semantico e gerar fallback indevido.
    $semanticInput = ([IO.File]::ReadAllText($InputPath)) | ConvertFrom-Json
    Mask-NativeImageAssetKeys -Node $semanticInput

    $utf8NoBomInput = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText(
        $tempInput,
        ($semanticInput | ConvertTo-Json -Depth 60),
        $utf8NoBomInput
    )

    # Suprime a saida intermediaria: a Etapa B exibe somente seu QA final.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $semanticResolver `
        -InputPath $tempInput `
        -OutputPath $tempResolved `
        -RepoRoot $RepoRoot | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "O resolver semantico Smart Assets retornou erro."
    }

    if (-not (Test-Path -LiteralPath $tempResolved -PathType Leaf)) {
        throw "O resolver semantico nao criou o JSON intermediario."
    }

    $content = ([IO.File]::ReadAllText($tempResolved)) | ConvertFrom-Json
    Restore-NativeImageAssetKeys -Node $content

    $compat = ([IO.File]::ReadAllText($compatPath)) | ConvertFrom-Json

    $events = @()
    $blockers = @()

    function Add-Event {
        param(
            [string]$Mechanic,
            [string]$Path,
            [string]$Requested,
            [string]$NativeField,
            [string]$Status,
            [string]$Strategy,
            [string]$File
        )

        $script:events += [pscustomobject][ordered]@{
            mechanic = $Mechanic
            path = $Path
            requested = $Requested
            nativeField = $NativeField
            status = $Status
            strategy = $Strategy
            file = $File
        }
    }

    function Add-Blocker {
        param(
            [string]$Mechanic,
            [string]$Path,
            [string]$Requested,
            [string]$Reason
        )

        $entry = [pscustomobject][ordered]@{
            mechanic = $Mechanic
            path = $Path
            requested = $Requested
            reason = $Reason
        }

        $script:blockers += $entry

        Add-Event `
            -Mechanic $Mechanic `
            -Path $Path `
            -Requested $Requested `
            -NativeField "" `
            -Status "blocked" `
            -Strategy "r124-compatibility-gate" `
            -File ""
    }

    function Resolution-Info {
        param([object]$Node)

        $resolution = Get-PropertyValue -Object $Node -Name "_assetResolution"
        $requested = Get-PropertyValue -Object $Node -Name "imageAsset"

        if ([string]::IsNullOrWhiteSpace([string]$requested)) {
            $requested = Get-PropertyValue -Object $Node -Name "imageAssetKey"
        }

        $status = ""
        $strategy = ""
        $file = ""

        if ($resolution -is [pscustomobject]) {
            $status = [string](Get-PropertyValue -Object $resolution -Name "status")
            $strategy = [string](Get-PropertyValue -Object $resolution -Name "strategy")
            $file = [string](Get-PropertyValue -Object $resolution -Name "file")
        }

        return [pscustomobject][ordered]@{
            requested = [string]$requested
            status = $status
            strategy = $strategy
            file = $file
        }
    }

    function Apply-TargetShooter {
        param([object]$Config, [string]$Path)

        $items = Get-PropertyValue -Object $Config -Name "items"
        if ($items -isnot [System.Array]) { return }

        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            if ($item -isnot [pscustomobject]) { continue }

            $url = [string](Get-PropertyValue -Object $item -Name "imageUrl")
            if ([string]::IsNullOrWhiteSpace($url)) { continue }

            Set-PropertyValue -Object $item -Name "image" -Value $url
            $info = Resolution-Info -Node $item

            Add-Event `
                -Mechanic "target-shooter" `
                -Path ($Path + ".items[" + $i + "]") `
                -Requested $info.requested `
                -NativeField "image" `
                -Status $info.status `
                -Strategy $info.strategy `
                -File $info.file
        }
    }

    function Apply-Matching {
        param([object]$Config, [string]$Path)

        $assets = Ensure-ObjectProperty -Object $Config -Name "assets"
        $sources = Get-PropertyValue -Object $Config -Name "assetSources"

        if ($sources -is [pscustomobject]) {
            foreach ($property in @($sources.PSObject.Properties)) {
                $key = [string]$property.Name
                $source = $property.Value

                if ($source -isnot [pscustomobject]) { continue }

                $url = [string](Get-PropertyValue -Object $source -Name "imageUrl")
                if ([string]::IsNullOrWhiteSpace($url)) { continue }

                Set-PropertyValue -Object $assets -Name $key -Value $url
                $info = Resolution-Info -Node $source

                Add-Event `
                    -Mechanic "matching" `
                    -Path ($Path + ".assetSources." + $key) `
                    -Requested $info.requested `
                    -NativeField ("assets." + $key) `
                    -Status $info.status `
                    -Strategy $info.strategy `
                    -File $info.file
            }
        }

        foreach ($sideName in @("leftItems", "rightItems")) {
            $side = Get-PropertyValue -Object $Config -Name $sideName
            if ($side -isnot [System.Array]) { continue }

            for ($i = 0; $i -lt $side.Count; $i++) {
                $item = $side[$i]
                if ($item -isnot [pscustomobject]) { continue }

                $url = [string](Get-PropertyValue -Object $item -Name "imageUrl")
                if ([string]::IsNullOrWhiteSpace($url)) { continue }

                $id = [string](Get-PropertyValue -Object $item -Name "id")
                if ([string]::IsNullOrWhiteSpace($id)) {
                    $id = $sideName + "-" + ($i + 1)
                }

                $assetKey = "smart-" + (Normalize-Key $id)
                $assetKey = $assetKey -replace '\s+', '-'

                Set-PropertyValue -Object $assets -Name $assetKey -Value $url
                Set-PropertyValue -Object $item -Name "imageAssetKey" -Value $assetKey

                $info = Resolution-Info -Node $item

                Add-Event `
                    -Mechanic "matching" `
                    -Path ($Path + "." + $sideName + "[" + $i + "]") `
                    -Requested $info.requested `
                    -NativeField ("assets." + $assetKey + " + imageAssetKey") `
                    -Status $info.status `
                    -Strategy $info.strategy `
                    -File $info.file
            }
        }
    }

    function Apply-ImageSrcObject {
        param(
            [object]$Node,
            [string]$Mechanic,
            [string]$Path,
            [string]$NativeField
        )

        if ($Node -isnot [pscustomobject]) { return }

        $url = [string](Get-PropertyValue -Object $Node -Name "imageUrl")
        if ([string]::IsNullOrWhiteSpace($url)) { return }

        $image = Get-PropertyValue -Object $Node -Name "image"

        if ($image -is [pscustomobject]) {
            Set-PropertyValue -Object $image -Name "src" -Value $url
        }
        else {
            $image = [pscustomobject][ordered]@{
                src = $url
            }
            Set-PropertyValue -Object $Node -Name "image" -Value $image
        }

        $info = Resolution-Info -Node $Node

        Add-Event `
            -Mechanic $Mechanic `
            -Path $Path `
            -Requested $info.requested `
            -NativeField $NativeField `
            -Status $info.status `
            -Strategy $info.strategy `
            -File $info.file
    }

    function Apply-DragDrop {
        param([object]$Question, [object]$Config, [string]$Path)

        foreach ($name in @("targets", "items")) {
            $list = Get-PropertyValue -Object $Config -Name $name
            if ($list -isnot [System.Array]) { continue }

            for ($i = 0; $i -lt $list.Count; $i++) {
                Apply-ImageSrcObject `
                    -Node $list[$i] `
                    -Mechanic "drag-drop" `
                    -Path ($Path + "." + $name + "[" + $i + "]") `
                    -NativeField "image.src"
            }
        }

        $questionTargets = Get-PropertyValue -Object $Question -Name "targets"
        if ($questionTargets -is [System.Array]) {
            for ($i = 0; $i -lt $questionTargets.Count; $i++) {
                Apply-ImageSrcObject `
                    -Node $questionTargets[$i] `
                    -Mechanic "drag-drop" `
                    -Path ($Path + ".__question.targets[" + $i + "]") `
                    -NativeField "image.src"
            }
        }

        $alternatives = Get-PropertyValue -Object $Question -Name "alternatives"
        if ($alternatives -is [System.Array]) {
            for ($i = 0; $i -lt $alternatives.Count; $i++) {
                Apply-ImageSrcObject `
                    -Node $alternatives[$i] `
                    -Mechanic "drag-drop" `
                    -Path ($Path + ".__question.alternatives[" + $i + "]") `
                    -NativeField "image.src"
            }
        }
    }

    function Apply-SmartSentence {
        param([object]$Config, [string]$Path)

        $url = [string](Get-PropertyValue -Object $Config -Name "imageUrl")

        if (-not [string]::IsNullOrWhiteSpace($url)) {
            Set-PropertyValue -Object $Config -Name "imageSrc" -Value $url
            $info = Resolution-Info -Node $Config

            Add-Event `
                -Mechanic "smart-sentence" `
                -Path $Path `
                -Requested $info.requested `
                -NativeField "imageSrc" `
                -Status $info.status `
                -Strategy $info.strategy `
                -File $info.file
        }

        foreach ($listName in @("words", "tokens", "items", "options", "bank")) {
            $list = Get-PropertyValue -Object $Config -Name $listName
            if ($list -isnot [System.Array]) { continue }

            for ($i = 0; $i -lt $list.Count; $i++) {
                if ($list[$i] -is [pscustomobject]) {
                    Apply-ImageSrcObject `
                        -Node $list[$i] `
                        -Mechanic "smart-sentence" `
                        -Path ($Path + "." + $listName + "[" + $i + "]") `
                        -NativeField "image.src"
                }
            }
        }
    }

    function Get-BubbleCompatKey {
        param([string]$Requested)

        $normalized = Normalize-Key $Requested
        if ([string]::IsNullOrWhiteSpace($normalized)) { return "" }

        foreach ($property in @($compat.map.PSObject.Properties)) {
            if ((Normalize-Key ([string]$property.Name)) -eq $normalized) {
                return [string]$property.Value
            }
        }

        return ""
    }

    function Apply-BubblePop {
        param([object]$Question, [string]$Path)

        $alternatives = Get-PropertyValue -Object $Question -Name "alternatives"
        if ($alternatives -isnot [System.Array]) { return }

        for ($i = 0; $i -lt $alternatives.Count; $i++) {
            $item = $alternatives[$i]
            if ($item -isnot [pscustomobject]) { continue }

            $requested = [string](Get-PropertyValue -Object $item -Name "imageAsset")

            if ([string]::IsNullOrWhiteSpace($requested)) {
                continue
            }

            $url = [string](Get-PropertyValue -Object $item -Name "imageUrl")
            $info = Resolution-Info -Node $item
            $itemPath = $Path + ".alternatives[" + $i + "]"

            if ([string]::IsNullOrWhiteSpace($url)) {
                Add-Blocker `
                    -Mechanic "bubble-pop" `
                    -Path $itemPath `
                    -Requested $requested `
                    -Reason "Smart Assets nao resolveu URL para este asset."
                continue
            }

            $legacyKey = Get-BubbleCompatKey -Requested $requested

            if ([string]::IsNullOrWhiteSpace($legacyKey)) {
                Add-Blocker `
                    -Mechanic "bubble-pop" `
                    -Path $itemPath `
                    -Requested $requested `
                    -Reason "Bubble Pop R124 exige metadata.imageAssetKey conhecido. O asset semantico nao possui ponte aprovada."
                continue
            }

            $metadata = Ensure-ObjectProperty -Object $item -Name "metadata"
            Set-PropertyValue -Object $metadata -Name "imageAssetKey" -Value $legacyKey
            Set-PropertyValue -Object $metadata -Name "smartAssetsResolvedUrl" -Value $url

            $image = Ensure-ObjectProperty -Object $item -Name "image"
            $alt = [string](Get-PropertyValue -Object $image -Name "alt")

            if ([string]::IsNullOrWhiteSpace($alt)) {
                $text = [string](Get-PropertyValue -Object $item -Name "text")
                if ([string]::IsNullOrWhiteSpace($text)) {
                    $text = $requested
                }
                Set-PropertyValue -Object $image -Name "alt" -Value $text
            }

            Add-Event `
                -Mechanic "bubble-pop" `
                -Path $itemPath `
                -Requested $requested `
                -NativeField "metadata.imageAssetKey" `
                -Status $info.status `
                -Strategy ("r124-bridge:" + $legacyKey) `
                -File $info.file
        }
    }

    function Mechanic-Of {
        param([object]$Node)

        $mechanic = [string](Get-PropertyValue -Object $Node -Name "mechanic")
        if (-not [string]::IsNullOrWhiteSpace($mechanic)) {
            return $mechanic.ToLowerInvariant()
        }

        $delivery = Get-PropertyValue -Object $Node -Name "delivery"
        if ($delivery -is [pscustomobject]) {
            $mechanic = [string](Get-PropertyValue -Object $delivery -Name "mechanic")
            if (-not [string]::IsNullOrWhiteSpace($mechanic)) {
                return $mechanic.ToLowerInvariant()
            }
        }

        return ""
    }

    function Walk-Node {
        param(
            [object]$Node,
            [string]$Path = '$',
            [string]$InheritedMechanic = ""
        )

        if ($null -eq $Node) { return }

        if ($Node -is [System.Array]) {
            for ($i = 0; $i -lt $Node.Count; $i++) {
                Walk-Node -Node $Node[$i] -Path ($Path + "[" + $i + "]") -InheritedMechanic $InheritedMechanic
            }
            return
        }

        if ($Node -isnot [pscustomobject]) { return }

        $mechanic = Mechanic-Of -Node $Node
        if ([string]::IsNullOrWhiteSpace($mechanic)) {
            $mechanic = $InheritedMechanic
        }

        $metadata = Get-PropertyValue -Object $Node -Name "metadata"
        $hasDragDropConfig = $false

        if ($metadata -is [pscustomobject]) {
            $targetShooter = Get-PropertyValue -Object $metadata -Name "targetShooter"
            if ($targetShooter -is [pscustomobject]) {
                Apply-TargetShooter -Config $targetShooter -Path ($Path + ".metadata.targetShooter")
            }

            $matching = Get-PropertyValue -Object $metadata -Name "matching"
            if ($matching -is [pscustomobject]) {
                Apply-Matching -Config $matching -Path ($Path + ".metadata.matching")
            }

            $dragDrop = Get-PropertyValue -Object $metadata -Name "dragDrop"
            if ($dragDrop -is [pscustomobject]) {
                $hasDragDropConfig = $true
                Apply-DragDrop -Question $Node -Config $dragDrop -Path ($Path + ".metadata.dragDrop")
            }

            $smartSentence = Get-PropertyValue -Object $metadata -Name "smartSentence"
            if ($smartSentence -is [pscustomobject]) {
                Apply-SmartSentence -Config $smartSentence -Path ($Path + ".metadata.smartSentence")
            }
        }

        if ($mechanic -eq "bubble-pop") {
            Apply-BubblePop -Question $Node -Path $Path
        }

        if (
            $mechanic -eq "drag-drop" -and
            -not $hasDragDropConfig -and
            (
                (Has-Property -Object $Node -Name "alternatives") -or
                (Has-Property -Object $Node -Name "targets") -or
                (Has-Property -Object $Node -Name "items")
            )
        ) {
            $emptyConfig = [pscustomobject][ordered]@{}
            Apply-DragDrop -Question $Node -Config $emptyConfig -Path $Path
        }

        $propertyNames = @()
        foreach ($property in @($Node.PSObject.Properties)) {
            $propertyNames += [string]$property.Name
        }

        foreach ($propertyName in $propertyNames) {
            if ($propertyName -eq "_assetResolution") { continue }

            $child = Get-PropertyValue -Object $Node -Name $propertyName

            if ($child -is [pscustomobject] -or $child -is [System.Array]) {
                Walk-Node `
                    -Node $child `
                    -Path ($Path + "." + $propertyName) `
                    -InheritedMechanic $mechanic
            }
        }
    }

    Walk-Node -Node $content

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [IO.File]::WriteAllText(
        $OutputPath,
        ($content | ConvertTo-Json -Depth 60),
        $utf8NoBom
    )

    $byMechanic = [ordered]@{}
    foreach ($name in @("target-shooter", "matching", "drag-drop", "bubble-pop", "smart-sentence")) {
        $mechanicEvents = @($events | Where-Object { $_.mechanic -eq $name })
        $byMechanic[$name] = [ordered]@{
            total = $mechanicEvents.Count
            resolved = @($mechanicEvents | Where-Object { $_.status -eq "resolved" }).Count
            fallback = @($mechanicEvents | Where-Object { $_.status -eq "fallback" }).Count
            blocked = @($mechanicEvents | Where-Object { $_.status -eq "blocked" }).Count
        }
    }

    $fallbackCount = @($events | Where-Object { $_.status -eq "fallback" }).Count
    $blockedCount = $blockers.Count

    $report = [ordered]@{
        report = "DUDUQ_SMART_ASSETS_INTEGRATION_B"
        version = "1.0.1"
        generatedAt = (Get-Date).ToString("o")
        input = $InputPath
        output = $OutputPath
        policy = [ordered]@{
            engineBaseline = "Canary R124"
            engineMutation = $false
            bubblePopMode = "r124-compatibility-bridge"
            blockUnknownBubbleAsset = $true
        }
        counts = [ordered]@{
            events = $events.Count
            fallback = $fallbackCount
            blocked = $blockedCount
        }
        byMechanic = $byMechanic
        blockers = @($blockers)
        events = @($events)
    }

    $reportDir = [IO.Path]::GetDirectoryName($OutputPath)
    $reportBase = [IO.Path]::GetFileNameWithoutExtension($OutputPath)
    $reportPath = Join-Path $reportDir ($reportBase + ".assets-report.json")

    [IO.File]::WriteAllText(
        $reportPath,
        ($report | ConvertTo-Json -Depth 30),
        $utf8NoBom
    )

    Write-Host ""
    Write-Host "DUDUQ SMART ASSETS - ETAPA B" -ForegroundColor Cyan
    Write-Host ("Eventos integrados: " + $events.Count)
    Write-Host ("Fallbacks: " + $fallbackCount)
    Write-Host ("Bloqueios de compatibilidade: " + $blockedCount)
    Write-Host ""

    foreach ($mechanicName in @($byMechanic.Keys)) {
        $stats = $byMechanic[$mechanicName]
        Write-Host (
            "- " + $mechanicName +
            ": total=" + $stats.total +
            " | resolved=" + $stats.resolved +
            " | fallback=" + $stats.fallback +
            " | blocked=" + $stats.blocked
        )
    }

    Write-Host ""
    Write-Host ("Saida: " + $OutputPath)
    Write-Host ("QA: " + $reportPath)

    if ($blockedCount -gt 0) {
        Write-Host ""
        Write-Host "ETAPA B: BLOQUEADA PARA PUBLICACAO." -ForegroundColor Red
        Write-Host "Revise o relatorio. Nenhum asset Bubble Pop desconhecido sera chutado." -ForegroundColor Yellow
        exit 4
    }

    if ($fallbackCount -gt 0) {
        Write-Host ""
        Write-Host "ATENCAO: existem fallbacks. Revise o QA antes de publicar." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "ETAPA B: CONTEUDO ADAPTADO." -ForegroundColor Green
}
finally {
    foreach ($temporaryFile in @($tempInput, $tempResolved)) {
        if ($temporaryFile -and (Test-Path -LiteralPath $temporaryFile -PathType Leaf)) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }

    if ($tempResolved) {
        $tempReport = [IO.Path]::Combine(
            [IO.Path]::GetDirectoryName($tempResolved),
            [IO.Path]::GetFileNameWithoutExtension($tempResolved) + ".assets-report.json"
        )

        if (Test-Path -LiteralPath $tempReport -PathType Leaf) {
            Remove-Item -LiteralPath $tempReport -Force
        }
    }
}

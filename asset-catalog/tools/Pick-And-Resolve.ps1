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

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Find-AssetsRepo
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$resolver = Join-Path $RepoRoot "asset-catalog\tools\Resolve-DuduQContent.ps1"
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) {
    throw "Smart Assets ainda nao esta instalado no Assets-DuduQ. Execute o reparo/instalacao primeiro."
}

Add-Type -AssemblyName System.Windows.Forms

$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "Escolha o JSON de conteudo DuduQ"
$dialog.Filter = "JSON (*.json)|*.json|Todos os arquivos (*.*)|*.*"
$dialog.CheckFileExists = $true
$dialog.Multiselect = $false

$downloads = Join-Path $env:USERPROFILE "Downloads"
if (Test-Path -LiteralPath $downloads -PathType Container) {
    $dialog.InitialDirectory = $downloads
}

$result = $dialog.ShowDialog()

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Selecao cancelada. Nenhum arquivo foi alterado." -ForegroundColor Yellow
    exit 2
}

$inputPath = $dialog.FileName

Write-Host ""
Write-Host ("JSON selecionado: " + $inputPath) -ForegroundColor Cyan
Write-Host ""

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver -InputPath $inputPath -RepoRoot $RepoRoot
exit $LASTEXITCODE

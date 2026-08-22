param(
    [string]$RepoRoot = "",
    [int]$Port = 8777
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

function Get-ContentType([string]$Extension) {
    switch ($Extension.ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".csv" { return "text/csv; charset=utf-8" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        ".svg" { return "image/svg+xml; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Find-AssetsRepo }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$catalog = Join-Path $RepoRoot "asset-catalog\assets-index.json"
if (-not (Test-Path -LiteralPath $catalog -PathType Leaf)) {
    throw "assets-index.json nao encontrado. Execute ATUALIZAR_CATALOGO.bat."
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host ""
    Write-Host "DUDUQ SMART ASSETS - TESTE LOCAL ATIVO" -ForegroundColor Green
    Write-Host ("Repositorio: " + $RepoRoot)
    Write-Host ("Endereco: " + $prefix)
    Write-Host "Feche esta janela ao terminar." -ForegroundColor Yellow

    Start-Process ($prefix + "asset-catalog/test/index.html?ts=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            $relative = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart("/"))
            if ([string]::IsNullOrWhiteSpace($relative)) {
                $relative = "asset-catalog/test/index.html"
            }

            $candidate = Join-Path $RepoRoot ($relative.Replace("/","\"))
            $full = [IO.Path]::GetFullPath($candidate)

            if (-not $full.StartsWith($RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $ctx.Response.StatusCode = 403
                $ctx.Response.Close()
                continue
            }

            if (Test-Path -LiteralPath $full -PathType Container) {
                $full = Join-Path $full "index.html"
            }

            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                $ctx.Response.StatusCode = 404
                $ctx.Response.Close()
                continue
            }

            $bytes = [IO.File]::ReadAllBytes($full)
            $ctx.Response.StatusCode = 200
            $ctx.Response.ContentType = Get-ContentType ([IO.Path]::GetExtension($full))
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
            $ctx.Response.Headers["Pragma"] = "no-cache"
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $ctx.Response.Close()
        }
        catch {
            try {
                $ctx.Response.StatusCode = 500
                $ctx.Response.Close()
            } catch {}
        }
    }
}
finally {
    try { $listener.Stop(); $listener.Close() } catch {}
}

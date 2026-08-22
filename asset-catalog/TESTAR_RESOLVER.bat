@echo off
setlocal
title DuduQ Smart Assets - Testar Resolver
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Start-AssetCatalogServer.ps1"
echo.
pause

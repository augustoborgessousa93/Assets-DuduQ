@echo off
setlocal
title DuduQ Smart Assets - Atualizar Catalogo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Build-AssetCatalog.ps1"
echo.
pause

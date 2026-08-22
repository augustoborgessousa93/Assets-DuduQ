@echo off
setlocal
title DuduQ Smart Assets - Resolver Conteudo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Pick-And-Resolve.ps1"
echo.
pause

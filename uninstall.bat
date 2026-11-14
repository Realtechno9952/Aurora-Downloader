@echo off
title Aurora Downloader - uninstall
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0host\uninstall.ps1" %*
echo.
pause

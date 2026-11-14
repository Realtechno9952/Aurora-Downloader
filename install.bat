@echo off
title Aurora Downloader - install
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0host\install.ps1" %*
echo.
pause

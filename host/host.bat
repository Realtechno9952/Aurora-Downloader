@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0host.ps1"

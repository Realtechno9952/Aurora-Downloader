# Aurora Downloader 2.0.0 beta 2 - builds dist\aurora-downloader-<version>-extension.zip from the extension folder.
# The same zip works for both stores: upload it at addons.mozilla.org (Developer Hub > "On your own") to get a signed
# Firefox .xpi, or at the Chrome Web Store / Edge Add-ons. (Store-published Chromium copies get their own extension ID:
# pass it to install.ps1 with -ExtraExtensionIds.)
# (Windows PowerShell's Compress-Archive writes backslashes in the zip, which Firefox rejects, so this does it properly.)
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ext = Join-Path $root 'extension'
$manifest = Get-Content -LiteralPath (Join-Path $ext 'manifest.json') -Raw | ConvertFrom-Json
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zipPath = Join-Path $dist ('aurora-downloader-' + $manifest.version + '-extension.zip')
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($f in Get-ChildItem -LiteralPath $ext -Recurse -File) {
        $rel = $f.FullName.Substring($ext.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, 'Optimal')
    }
} finally {
    $zip.Dispose()
}
Write-Host ('Built ' + $zipPath) -ForegroundColor Green

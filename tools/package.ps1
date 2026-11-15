# Aurora Downloader 2.0.0 beta 4 - builds the extension zips in dist\ for the stores:
#   aurora-downloader-<version>-firefox.zip    upload at addons.mozilla.org (Developer Hub > "On your own") to get a signed .xpi
#   aurora-downloader-<version>-chromium.zip   for the Chrome Web Store / Edge Add-ons
# A store-published Chromium copy gets its own extension ID: pass it to install.ps1 with -ExtraExtensionIds.
# (Windows PowerShell's Compress-Archive writes backslashes in the zip, which Firefox rejects, so this does it properly.)
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ext = Join-Path $root 'extension'
$version = (Get-Content -LiteralPath (Join-Path $ext 'manifest.json') -Raw | ConvertFrom-Json).version
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# $leaveOut is the manifest the browser must not see; $useAsManifest is the one that becomes manifest.json.
function New-ExtensionZip([string]$zipPath, [string]$leaveOut, [string]$useAsManifest) {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        foreach ($f in Get-ChildItem -LiteralPath $ext -Recurse -File) {
            $rel = $f.FullName.Substring($ext.Length + 1).Replace('\', '/')
            if ($rel -eq $leaveOut) { continue }
            if ($rel -eq $useAsManifest) { $rel = 'manifest.json' }
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, 'Optimal')
        }
    } finally {
        $zip.Dispose()
    }
    Write-Host ('Built ' + $zipPath) -ForegroundColor Green
}

New-ExtensionZip (Join-Path $dist ('aurora-downloader-' + $version + '-firefox.zip')) 'manifest.chromium.json' 'manifest.json'
New-ExtensionZip (Join-Path $dist ('aurora-downloader-' + $version + '-chromium.zip')) 'manifest.json' 'manifest.chromium.json'

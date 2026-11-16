# Aurora Downloader 2.0.0 beta 4.5 - uninstaller for the helper (Firefox and Chromium browsers).
# Removes everything the installer added. Your downloaded videos are never touched.
#   uninstall.ps1                remove the helper registration
#   uninstall.ps1 -WhatIf        show what would be removed, change nothing
#   uninstall.ps1 -IncludeTools  also offer to remove yt-dlp, ffmpeg and deno (installed with winget)
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$IncludeTools,
    [switch]$NoRegistry          # for testing: do not touch the registry
)
$ErrorActionPreference = 'Stop'
$HostName     = 'yt_dlp_host'
$Here         = $PSScriptRoot
$ChromiumDir   = Join-Path (Split-Path $Here -Parent) 'extension-chromium'
$Browsers     = @(
    @{ Name = 'Firefox';  Kind = 'firefox';  Key = "HKCU:\Software\Mozilla\NativeMessagingHosts\$HostName" },
    @{ Name = 'Chrome';   Kind = 'chromium'; Key = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HostName" },
    @{ Name = 'Edge';     Kind = 'chromium'; Key = "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$HostName" },
    @{ Name = 'Brave';    Kind = 'chromium'; Key = "HKCU:\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\$HostName" },
    @{ Name = 'Chromium'; Kind = 'chromium'; Key = "HKCU:\Software\Chromium\NativeMessagingHosts\$HostName" }
)
$ManifestPath = Join-Path $Here ($HostName + '.json')
$ChromiumManifestPath = Join-Path $Here ($HostName + '_chromium.json')
$script:problems = 0

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Ok([string]$t)   { Say ('  [ok]      ' + $t) 'Green' }
function Note([string]$t) { Say ('  [note]    ' + $t) 'Yellow' }
function Bad([string]$t)  { Say ('  [FAILED]  ' + $t) 'Red'; $script:problems++ }

Say ''
Say 'Aurora Downloader - uninstall' 'Cyan'
Say ''
Say '1. Removing the helper registration'
$onWindows = ($env:OS -eq 'Windows_NT')
if ($onWindows -and -not $NoRegistry) {
    foreach ($b in $Browsers) {
        try {
            if (Test-Path $b.Key) {
                if ($PSCmdlet.ShouldProcess($b.Key, ('Remove the ' + $b.Name + ' registry entry'))) {
                    Remove-Item -Path $b.Key -Recurse -Force
                    Ok ('Removed the entry ' + $b.Name + ' used to find the helper')
                }
            } else {
                Note ($b.Name + ': the helper was not registered (nothing to remove)')
            }
        } catch {
            Bad ('Could not remove the ' + $b.Name + ' registry entry: ' + $_.Exception.Message)
        }
    }
}
foreach ($mp in @($ManifestPath, $ChromiumManifestPath)) {
    try {
        if (Test-Path -LiteralPath $mp) {
            if ($PSCmdlet.ShouldProcess($mp, 'Delete the generated helper manifest')) {
                Remove-Item -LiteralPath $mp -Force
                Ok ('Deleted ' + (Split-Path $mp -Leaf))
            }
        } else {
            Note ('No ' + (Split-Path $mp -Leaf) + ' to delete')
        }
    } catch {
        Bad ('Could not delete ' + $mp + ': ' + $_.Exception.Message)
    }
}

# The Chromium copy of the extension is made by install.ps1, so it can go too.
try {
    if (Test-Path -LiteralPath $ChromiumDir) {
        if ($PSCmdlet.ShouldProcess($ChromiumDir, 'Delete the generated Chromium copy of the extension')) {
            Remove-Item -LiteralPath $ChromiumDir -Recurse -Force
            Ok 'Deleted the extension-chromium folder'
        }
    }
} catch {
    Bad ('Could not delete ' + $ChromiumDir + ': ' + $_.Exception.Message)
}

# Check it really is gone.
if (-not $WhatIfPreference) {
    $still = $false
    if ($onWindows -and -not $NoRegistry) { foreach ($b in $Browsers) { if (Test-Path $b.Key) { $still = $true } } }
    foreach ($mp in @($ManifestPath, $ChromiumManifestPath)) { if (Test-Path -LiteralPath $mp) { $still = $true } }
    if ($still) { Bad 'Something is still there. Close your browser and run this again.' } else { Ok 'Verified: no browser can start the helper any more' }
}

if ($IncludeTools) {
    Say ''
    Say '2. yt-dlp, ffmpeg and deno'
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wg) {
        Note 'winget was not found, so these were not touched.'
    } elseif ($PSCmdlet.ShouldContinue('Other programs may use yt-dlp, ffmpeg or deno. Remove them from this computer?', 'Remove the tools too?')) {
        foreach ($id in 'yt-dlp.yt-dlp', 'yt-dlp.FFmpeg', 'DenoLand.Deno') {
            if ($PSCmdlet.ShouldProcess($id, 'winget uninstall')) {
                & $wg.Source uninstall --id $id --exact --silent --disable-interactivity 2>&1 | Out-Null
                Ok ('Asked winget to remove ' + $id)
            }
        }
    } else {
        Note 'Left the tools installed.'
    }
}

Say ''
Say 'Two things are left, and only you can do them:' 'Cyan'
Say '  1. Remove "Aurora Downloader" on your browser extensions page (Firefox: about:addons, Chrome/Edge/Brave: chrome://extensions).'
Say '     (A temporary Firefox add-on also disappears when Firefox restarts.)'
Say '     Its settings and history are removed with it.'
Say '  2. Delete this folder if you no longer want the files.'
Say ''
Say 'Your downloaded videos were not touched.'
if ($script:problems -gt 0) { exit 1 }
exit 0

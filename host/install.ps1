# Aurora Downloader 2.0.0 beta 4.5 - installer for the helper (Firefox, Chrome, Edge, Brave and other Chromium browsers).
# Registers the helper for the current Windows user (no administrator rights needed), then tests it.
#   install.ps1          register and test
#   install.ps1 -Check   only test, change nothing
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$NoRegistry,         # for testing: do not touch the registry
    [string]$HostCommand = '',   # for testing: start the helper with this command instead of host.bat
    [string[]]$ExtraExtensionIds = @()   # extra Chromium extension IDs allowed to use the helper (e.g. a store-published copy)
)
$ErrorActionPreference = 'Stop'
$HostName     = 'yt_dlp_host'
$FirefoxId    = 'ytdlp-launcher@local'
$ChromiumId   = 'lnmopdhkcppijnmfakppmeimnabbhmko'   # fixed by the "key" in extension/manifest.json, so Chrome, Edge and Brave always get the same ID
$Here         = $PSScriptRoot
$ExtensionDir  = Join-Path (Split-Path $Here -Parent) 'extension'
$ChromiumDir   = Join-Path (Split-Path $Here -Parent) 'extension-chromium'
$Browsers     = @(
    @{ Name = 'Firefox';  Kind = 'firefox';  Key = "HKCU:\Software\Mozilla\NativeMessagingHosts\$HostName" },
    @{ Name = 'Chrome';   Kind = 'chromium'; Key = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HostName" },
    @{ Name = 'Edge';     Kind = 'chromium'; Key = "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$HostName" },
    @{ Name = 'Brave';    Kind = 'chromium'; Key = "HKCU:\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\$HostName" },
    @{ Name = 'Chromium'; Kind = 'chromium'; Key = "HKCU:\Software\Chromium\NativeMessagingHosts\$HostName" }
)
$Launcher     = Join-Path $Here 'host.bat'
if ($HostCommand) { $Launcher = $HostCommand }
$ManifestPath = Join-Path $Here ($HostName + '.json')
$ChromiumManifestPath = Join-Path $Here ($HostName + '_chromium.json')
$script:problems = 0

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Ok([string]$t)   { Say ('  [ok]      ' + $t) 'Green' }
function Note([string]$t) { Say ('  [note]    ' + $t) 'Yellow' }
function Bad([string]$t)  { Say ('  [FAILED]  ' + $t) 'Red'; $script:problems++ }

# Start the helper the way the browser does, send it one message, and read its answer.
function Invoke-HostMessage([string]$launcher, [hashtable]$msg, [int]$timeoutMs = 30000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $launcher
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($msg | ConvertTo-Json -Compress))
        $in = $p.StandardInput.BaseStream
        $in.Write([BitConverter]::GetBytes([int]$bytes.Length), 0, 4)
        $in.Write($bytes, 0, $bytes.Length)
        $in.Flush()
        $out = $p.StandardOutput.BaseStream
        $lenBuf = New-Object byte[] 4
        $task = $out.ReadAsync($lenBuf, 0, 4)
        if (-not $task.Wait($timeoutMs)) { throw 'The helper did not answer in time.' }
        if ($task.Result -lt 4) { throw 'The helper closed without answering.' }
        $len = [BitConverter]::ToInt32($lenBuf, 0)
        $buf = New-Object byte[] $len
        $got = 0
        while ($got -lt $len) {
            $r = $out.Read($buf, $got, $len - $got)
            if ($r -le 0) { break }
            $got += $r
        }
        return ([Text.Encoding]::UTF8.GetString($buf, 0, $got) | ConvertFrom-Json)
    } finally {
        try { $p.StandardInput.Close() } catch {}
        if (-not $p.WaitForExit(3000)) { try { $p.Kill() } catch {} }
    }
}

Say ''
Say 'Aurora Downloader - helper setup' 'Cyan'
Say ''
Say '1. Checking this computer'
$onWindows = ($env:OS -eq 'Windows_NT')
if ($onWindows) { Ok ('Windows, PowerShell ' + $PSVersionTable.PSVersion) }
elseif ($NoRegistry) { Note 'Not Windows: running in test mode.' }
else { Bad 'This helper only works on Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 5) { Bad 'PowerShell 5.1 or newer is needed (it comes with Windows 10 and 11).' }
if ($Here -match '[^\x00-\x7F]') { Note 'This folder path has non-English characters. If your browser cannot start the helper, move the whole folder to a simple path such as C:\Tools\aurora-downloader and run this again.' }
if ($Here.Length -gt 180) { Note 'This folder path is very long. A short one such as C:\Tools\aurora-downloader is safer.' }
foreach ($f in 'host.ps1', 'host.bat') {
    if (-not (Test-Path -LiteralPath (Join-Path $Here $f))) { Bad ('A file is missing: ' + $f) }
}
if ($onWindows) {
    function Test-AppPath([string[]]$exe, [string[]]$extra) {
        foreach ($e in $exe) {
            foreach ($root in 'HKLM:', 'HKCU:') { if (Test-Path ($root + '\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\' + $e)) { return $true } }
        }
        foreach ($k in $extra) { if (Test-Path $k) { return $true } }
        return $false
    }
    $seen = @()
    if (Test-AppPath @('firefox.exe') @('HKLM:\SOFTWARE\Mozilla\Mozilla Firefox', 'HKLM:\SOFTWARE\WOW6432Node\Mozilla\Mozilla Firefox', 'HKCU:\SOFTWARE\Mozilla\Mozilla Firefox')) { $seen += 'Firefox' }
    if (Test-AppPath @('chrome.exe') @()) { $seen += 'Chrome' }
    if (Test-AppPath @('msedge.exe') @()) { $seen += 'Edge' }
    if (Test-AppPath @('brave.exe') @()) { $seen += 'Brave' }
    if ($seen.Count -gt 0) { Ok ('Found: ' + ($seen -join ', ')) } else { Note "Couldn't find a supported browser in the usual places (fine if it is installed somewhere else)." }
}

if (-not $Check) {
    Say ''
    Say '2. Registering the helper with your browsers'
    try {
        if ($onWindows) {
            # Files from a downloaded zip carry a "came from the internet" mark that makes PowerShell hesitate.
            # Clear it only on this program's own files: the helper, the .bat files and the extension.
            $root = Split-Path $Here -Parent
            $own = @(Get-ChildItem -LiteralPath $Here -File -ErrorAction SilentlyContinue) +
                   @(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File -ErrorAction SilentlyContinue) +
                   @(Get-ChildItem -LiteralPath $ExtensionDir -Recurse -File -ErrorAction SilentlyContinue)
            $own | Unblock-File -ErrorAction SilentlyContinue
        }
        $ffManifest = [ordered]@{
            name               = $HostName
            description        = 'Runs yt-dlp for the Aurora Downloader extension'
            path               = $Launcher
            type               = 'stdio'
            allowed_extensions = @($FirefoxId)
        } | ConvertTo-Json
        $origins = @('chrome-extension://' + $ChromiumId + '/')
        foreach ($x in $ExtraExtensionIds) {
            if ($x -match '^[a-p]{32}$') { $origins += ('chrome-extension://' + $x + '/') } else { Note ('Ignored an extension ID that does not look right: ' + $x) }
        }
        $crManifest = [ordered]@{
            name            = $HostName
            description     = 'Runs yt-dlp for the Aurora Downloader extension'
            path            = $Launcher
            type            = 'stdio'
            allowed_origins = @($origins)
        } | ConvertTo-Json
        # UTF-8 without a BOM, which is what the browsers expect.
        [IO.File]::WriteAllText($ManifestPath, $ffManifest, (New-Object Text.UTF8Encoding $false))
        [IO.File]::WriteAllText($ChromiumManifestPath, $crManifest, (New-Object Text.UTF8Encoding $false))
        Ok ('Wrote ' + $ManifestPath)
        Ok ('Wrote ' + $ChromiumManifestPath)
        if (-not $NoRegistry) {
            foreach ($b in $Browsers) {
                $mp = $ManifestPath
                if ($b.Kind -eq 'chromium') { $mp = $ChromiumManifestPath }
                New-Item -Path $b.Key -Force | Out-Null
                Set-ItemProperty -Path $b.Key -Name '(Default)' -Value $mp
                Ok ('Registered for ' + $b.Name + ' (current user only)')
            }
        }
    } catch {
        Bad ('Could not register the helper: ' + $_.Exception.Message)
    }
}

if ($onWindows -and -not $NoRegistry) {
    foreach ($b in $Browsers) {
        $v = $null
        try { $v = (Get-ItemProperty -Path $b.Key -ErrorAction Stop).'(default)' } catch {}
        if ($v -and (Test-Path -LiteralPath $v)) { Ok ($b.Name + ' will be able to find the helper') }
        elseif ($Check) { Bad ($b.Name + ': the helper is not registered yet. Run install again without -Check.') }
        else { Bad ($b.Name + ': the registry entry is missing, or points to a file that is not there.') }
    }
}

if (-not $Check) {
    # Chromium browsers need a different manifest file, so they load their own copy of the extension.
    Say ''
    Say '3. Making the extension copy for Chrome, Edge and Brave'
    try {
        if (Test-Path -LiteralPath $ChromiumDir) { Remove-Item -LiteralPath $ChromiumDir -Recurse -Force }
        Copy-Item -LiteralPath $ExtensionDir -Destination $ChromiumDir -Recurse
        Remove-Item -LiteralPath (Join-Path $ChromiumDir 'manifest.json') -Force
        Move-Item -LiteralPath (Join-Path $ChromiumDir 'manifest.chromium.json') -Destination (Join-Path $ChromiumDir 'manifest.json')
        Ok ('Made ' + $ChromiumDir)
    } catch {
        Bad ('Could not make the Chromium copy: ' + $_.Exception.Message)
    }
}

Say ''
Say '4. Testing the helper'
$ping = $null
$chk = $null
try {
    $ping = Invoke-HostMessage $Launcher @{ action = 'ping' }
    Ok ('The helper answered (version ' + $ping.version + ', PowerShell ' + $ping.powershell + ')')
    $chk = Invoke-HostMessage $Launcher @{ action = 'check' }
} catch {
    Bad ('The helper did not work: ' + $_.Exception.Message)
}
if ($chk) {
    if ($chk.ok) {
        Ok ('yt-dlp found: ' + $chk.ytdlp)
        if ($chk.ffmpeg) { Ok 'ffmpeg found' } else { Note 'ffmpeg was not found. Videos need it to merge video and audio. Install it with:  winget install yt-dlp.FFmpeg' }
        if (-not $chk.deno) { Note 'deno was not found. YouTube downloads may fail without it:  winget install DenoLand.Deno' }
    } else {
        Note 'yt-dlp was not found. Install it with:  winget install yt-dlp.yt-dlp'
        Note 'No winget? Put yt-dlp.exe and ffmpeg.exe in the "bin" folder next to host.ps1 instead.'
    }
}
if ($onWindows) {
    if (Get-Command winget -ErrorAction SilentlyContinue) { Ok 'winget is available (the extension uses it for updates)' }
    else { Note 'winget was not found. Everything works, but ffmpeg updates have to be done by hand.' }
}

Say ''
if ($script:problems -gt 0) {
    Say ('Finished with ' + $script:problems + ' problem(s). Read the [FAILED] lines above.') 'Red'
    exit 1
}
if ($Check) { Say 'Everything looks good.' 'Green' }
else {
    Say 'All set. Now add the extension:' 'Green'
    Say '  Firefox:   open about:debugging#/runtime/this-firefox, click "Load Temporary Add-on..." and pick extension\manifest.json'
    Say '  Chrome, Edge, Brave, Helium:   open the extensions page (chrome://extensions, edge://extensions...), turn on Developer mode,'
    Say '             click "Load unpacked" and pick the extension-chromium folder'
    Say '  Vivaldi / Opera:   same as Chrome (they use the same helper entry; not tested by the author)'
    Say ('  Run install.bat again after you update the extension, so the Chromium copy is refreshed.')
}
exit 0

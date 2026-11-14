# Aurora Downloader 2.0.0 beta 2 - repository check. Run it before every commit or release (it also runs on GitHub).
# Catches: merge-conflict markers, scripts that do not parse, non-ASCII in .ps1/.bat, broken JSON,
# files the manifest points at that are missing, and a helper version that does not match the manifest.
[CmdletBinding()]
param([string]$Root = '')
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$errors = New-Object System.Collections.Generic.List[string]
$rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
function Rel([string]$p) { return $p.Substring($rootFull.Length).TrimStart('\', '/') }

$files = @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]dist[\\/]' })
$textExt = '.ps1', '.bat', '.js', '.json', '.css', '.html', '.md', '.yml', '.yaml', '.txt', '.svg'
foreach ($f in ($files | Where-Object { $textExt -contains $_.Extension.ToLower() })) {
    $raw = [IO.File]::ReadAllText($f.FullName)
    if ($raw -match '(?m)^(<{7} |>{7} )') { $errors.Add('Merge-conflict marker in ' + (Rel $f.FullName)) }
    if (($f.Extension -eq '.ps1' -or $f.Extension -eq '.bat') -and $raw -match '[^\x00-\x7F]') { $errors.Add('Non-ASCII character in ' + (Rel $f.FullName) + ' (PowerShell 5.1 may misread it)') }
    if ($f.Extension -eq '.json') { try { [void]($raw | ConvertFrom-Json) } catch { $errors.Add('Invalid JSON: ' + (Rel $f.FullName)) } }
}
foreach ($f in ($files | Where-Object { $_.Extension.ToLower() -eq '.ps1' })) {
    $perr = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$perr)
    foreach ($e in @($perr)) { if ($e) { $errors.Add('PowerShell syntax error in ' + (Rel $f.FullName) + ' line ' + $e.Extent.StartLineNumber + ': ' + $e.Message) } }
}

$manifestPath = Join-Path $rootFull 'extension/manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $m = $null
    try { $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch {}
    if ($m) {
        $extDir = Join-Path $rootFull 'extension'
        $need = New-Object System.Collections.Generic.List[string]
        foreach ($s in @($m.background.scripts)) { if ($s) { $need.Add([string]$s) } }
        if ($m.background.service_worker) { $need.Add([string]$m.background.service_worker) }
        if ($m.action.default_popup) { $need.Add([string]$m.action.default_popup) }
        foreach ($o in @($m.icons, $m.action.default_icon)) { if ($o) { foreach ($p in $o.PSObject.Properties) { $need.Add([string]$p.Value) } } }
        foreach ($n in $need) { if (-not (Test-Path -LiteralPath (Join-Path $extDir $n))) { $errors.Add('manifest.json points at a missing file: ' + $n) } }
        if ([int]$m.manifest_version -ne 3) { $errors.Add('manifest.json must be Manifest V3 (Chrome no longer runs V2)') }
        if ([string]$m.version -notmatch '^\d+(\.\d+){0,3}$') { $errors.Add('manifest.json version must be 1 to 4 plain numbers (Chrome rejects letters): ' + $m.version) }
        if ($m.key) {
            try {
                $der = [Convert]::FromBase64String([string]$m.key)
                $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($der)
                $hex = -join ($sha[0..15] | ForEach-Object { $_.ToString('x2') })
                $cid = -join ($hex.ToCharArray() | ForEach-Object { [char](97 + [Convert]::ToInt32([string]$_, 16)) })
                $inst = Join-Path $rootFull 'host/install.ps1'
                if (Test-Path -LiteralPath $inst) {
                    $im = [regex]::Match([IO.File]::ReadAllText($inst), "\`$ChromiumId\s*=\s*'([^']+)'")
                    if (-not $im.Success) { $errors.Add('install.ps1 has no $ChromiumId line') }
                    elseif ($im.Groups[1].Value -ne $cid) { $errors.Add('install.ps1 allows extension ID ' + $im.Groups[1].Value + ' but the manifest key gives ' + $cid) }
                }
            } catch { $errors.Add('manifest.json key is not valid base64') }
        } else { $errors.Add('manifest.json has no "key" (Chromium browsers would get a different extension ID on every computer)') }
        $hostPs1 = Join-Path $rootFull 'host/host.ps1'
        if (Test-Path -LiteralPath $hostPs1) {
            $hv = [regex]::Match([IO.File]::ReadAllText($hostPs1), "\`$script:Version\s*=\s*'([^']+)'")
            if (-not $hv.Success) { $errors.Add('host.ps1 has no $script:Version line') }
            elseif ($hv.Groups[1].Value -ne [string]$m.version) { $errors.Add('Version mismatch: manifest.json says ' + $m.version + ' but host.ps1 says ' + $hv.Groups[1].Value) }
        }
    }
} else {
    $errors.Add('extension/manifest.json is missing')
}

if ($errors.Count -gt 0) {
    Write-Host ('Check FAILED (' + $errors.Count + ' problem(s)):') -ForegroundColor Red
    foreach ($e in $errors) { Write-Host ('  - ' + $e) -ForegroundColor Red }
    exit 1
}
Write-Host ('Check passed: ' + $files.Count + ' files, no conflict markers, all scripts parse.') -ForegroundColor Green
exit 0

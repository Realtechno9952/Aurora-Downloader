# Aurora Downloader 2.0.0 beta 3 - repository check. Run it before every commit or release (it also runs on GitHub).
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

# Firefox loads extension/manifest.json. Chromium browsers load a copy of the extension in which
# manifest.chromium.json takes its place (install.ps1 makes that copy).
$extDir = Join-Path $rootFull 'extension'

function Read-Manifest([string]$name) {
    $path = Join-Path $extDir $name
    if (-not (Test-Path -LiteralPath $path)) { $errors.Add('extension/' + $name + ' is missing'); return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }  # bad JSON is reported above
}

function Test-Manifest($m, [string]$name) {
    if (-not $m) { return }
    if ([int]$m.manifest_version -ne 3) { $errors.Add($name + ' must be Manifest V3 (Chrome no longer runs V2)') }
    if ([string]$m.version -notmatch '^\d+(\.\d+){0,3}$') { $errors.Add($name + ': version must be 1 to 4 plain numbers (Chrome rejects letters): ' + $m.version) }
    $need = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($m.background.scripts)) { if ($s) { $need.Add([string]$s) } }
    if ($m.background.service_worker) { $need.Add([string]$m.background.service_worker) }
    if ($m.action.default_popup) { $need.Add([string]$m.action.default_popup) }
    foreach ($o in @($m.icons, $m.action.default_icon)) { if ($o) { foreach ($p in $o.PSObject.Properties) { $need.Add([string]$p.Value) } } }
    foreach ($n in $need) { if (-not (Test-Path -LiteralPath (Join-Path $extDir $n))) { $errors.Add($name + ' points at a missing file: ' + $n) } }
}

$ff = Read-Manifest 'manifest.json'
$cr = Read-Manifest 'manifest.chromium.json'
Test-Manifest $ff 'manifest.json'
Test-Manifest $cr 'manifest.chromium.json'

if ($ff) {
    # Firefox only runs background.scripts, and warns about the Chromium-only keys.
    if (-not $ff.background.scripts) { $errors.Add('manifest.json needs background.scripts (Firefox has no service workers)') }
    if ($ff.background.service_worker) { $errors.Add('manifest.json should not have background.service_worker (Firefox warns about it)') }
    if ($ff.key) { $errors.Add('manifest.json should not have a "key" (that is only for manifest.chromium.json)') }
}
if ($cr) {
    # Chrome rejects background.scripts in Manifest V3 and needs the key so the extension ID never changes.
    if (-not $cr.background.service_worker) { $errors.Add('manifest.chromium.json needs background.service_worker') }
    if ($cr.background.scripts) { $errors.Add('manifest.chromium.json must not have background.scripts (Chrome refuses to load it)') }
    if (-not $cr.key) {
        $errors.Add('manifest.chromium.json has no "key" (Chromium would give a different extension ID on every computer)')
    } else {
        try {
            $der = [Convert]::FromBase64String([string]$cr.key)
            $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($der)
            $hex = -join ($sha[0..15] | ForEach-Object { $_.ToString('x2') })
            $id = -join ($hex.ToCharArray() | ForEach-Object { [char](97 + [Convert]::ToInt32([string]$_, 16)) })
            $installPath = Join-Path $rootFull 'host/install.ps1'
            if (Test-Path -LiteralPath $installPath) {
                $found = [regex]::Match([IO.File]::ReadAllText($installPath), "\`$ChromiumId\s*=\s*'([^']+)'")
                if (-not $found.Success) { $errors.Add('install.ps1 has no $ChromiumId line') }
                elseif ($found.Groups[1].Value -ne $id) { $errors.Add('install.ps1 allows extension ID ' + $found.Groups[1].Value + ' but the key in manifest.chromium.json gives ' + $id) }
            }
        } catch { $errors.Add('The key in manifest.chromium.json is not valid base64') }
    }
}
if ($ff -and $cr -and ([string]$ff.version -ne [string]$cr.version)) { $errors.Add('The two manifests have different versions: ' + $ff.version + ' and ' + $cr.version) }

$hostPs1 = Join-Path $rootFull 'host/host.ps1'
if ($ff -and (Test-Path -LiteralPath $hostPs1)) {
    $found = [regex]::Match([IO.File]::ReadAllText($hostPs1), "\`$script:Version\s*=\s*'([^']+)'")
    if (-not $found.Success) { $errors.Add('host.ps1 has no $script:Version line') }
    elseif ($found.Groups[1].Value -ne [string]$ff.version) { $errors.Add('Version mismatch: the manifest says ' + $ff.version + ' but host.ps1 says ' + $found.Groups[1].Value) }
}

if ($errors.Count -gt 0) {
    Write-Host ('Check FAILED (' + $errors.Count + ' problem(s)):') -ForegroundColor Red
    foreach ($e in $errors) { Write-Host ('  - ' + $e) -ForegroundColor Red }
    exit 1
}
Write-Host ('Check passed: ' + $files.Count + ' files, no conflict markers, all scripts parse.') -ForegroundColor Green
exit 0

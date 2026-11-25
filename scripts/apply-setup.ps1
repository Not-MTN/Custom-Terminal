param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
trap {
  $failureLine = $_.InvocationInfo.ScriptLineNumber
  $failureSource = $_.InvocationInfo.Line
  [Console]::Error.WriteLine("Ghosty apply script failed at line ${failureLine}: $failureSource`n$($_.Exception.Message)")
  exit 1
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
Write-Output 'Ghosty: applying selected theme and tools.'
$setupWarnings = @()
$binDir = Join-Path $env:LOCALAPPDATA 'Ghosty/bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

function Add-GhostyBinToPath([string]$directory) {
  $userPath = [string][Environment]::GetEnvironmentVariable('Path','User')
  $pathEntries = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $directory })
  [Environment]::SetEnvironmentVariable('Path', (($directory + $pathEntries) -join ';'), 'User')
  $env:PATH = "$directory;$env:PATH"
}

function Verify-AssetDigest($asset, [string]$filePath, [string]$label) {
  if ($asset.digest -match '^sha256:(.+)$') {
    $expected = [string]$Matches[1]
    $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    if (-not [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)) { throw "SHA-256 verification failed for $label." }
  }
}

function Install-PortableTool([string]$tool) {
  $repos = @{ starship = 'starship/starship'; eza = 'eza-community/eza'; bat = 'sharkdp/bat' }
  $patterns = @{
    starship = '^starship-x86_64-pc-windows-msvc\.zip$'
    eza = '^eza\.exe_x86_64-pc-windows-gnu\.zip$'
    bat = '^bat-v.*x86_64-pc-windows-(gnu|msvc)\.zip$'
  }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($repos[$tool])/releases/latest" -Headers @{ 'User-Agent' = 'Ghosty-Terminal-Studio' }
  $asset = $release.assets | Where-Object { $_.name -match $patterns[$tool] } | Select-Object -First 1
  if (-not $asset) { throw "No Windows x64 release archive found for $tool." }
  $tempDir = Join-Path $env:TEMP "ghosty-$tool-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  try {
    $archive = Join-Path $tempDir $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive -UseBasicParsing
    Verify-AssetDigest $asset $archive $tool
    $extractDir = Join-Path $tempDir 'unpacked'
    Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
    $exe = Get-ChildItem -LiteralPath $extractDir -Filter "$tool.exe" -Recurse | Select-Object -First 1
    if (-not $exe) { throw "$tool.exe was missing from the official release archive." }
    Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $binDir "$tool.exe") -Force
    Add-GhostyBinToPath $binDir
    Write-Output "$tool installed from its official portable release."
  } finally {
    if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

function Install-PortableClink {
  $clinkDir = Join-Path $env:LOCALAPPDATA 'Ghosty/clink'
  $loader = Join-Path $clinkDir 'clink.bat'
  if (-not (Test-Path $loader)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/chrisant996/clink/releases/latest' -Headers @{ 'User-Agent' = 'Ghosty-Terminal-Studio' }
    $asset = $release.assets | Where-Object { $_.name -match '^clink\..+\.zip$' -and $_.name -notmatch 'symbols' } | Select-Object -First 1
    if (-not $asset) { throw 'No official Clink Windows ZIP was found.' }
    $tempDir = Join-Path $env:TEMP "ghosty-clink-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $tempDir,$clinkDir | Out-Null
    try {
      $archive = Join-Path $tempDir $asset.name
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive -UseBasicParsing
      Verify-AssetDigest $asset $archive 'Clink'
      Expand-Archive -LiteralPath $archive -DestinationPath $clinkDir -Force
    } finally {
      if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }
  if (-not (Test-Path $loader)) { throw 'clink.bat was not found in the official Clink archive.' }
  & $loader autorun install
  if ($LASTEXITCODE -ne 0) { throw "Clink autorun registration failed (exit $LASTEXITCODE)." }
  Write-Output 'Clink installed and enabled for Command Prompt.'
}

function Install-GhostyNerdFont {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $api = 'https://api.github.com/repos/ryanoasis/nerd-fonts/contents/patched-fonts/CascadiaCode/CaskaydiaCoveNerdFontMono-Regular.ttf'
  $fontInfo = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Ghosty-Terminal-Studio' }
  $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Fonts'
  New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
  $fontPath = Join-Path $fontDir 'CaskaydiaCoveNerdFontMono-Regular.ttf'
  Invoke-WebRequest -Uri $fontInfo.download_url -OutFile $fontPath -UseBasicParsing
  $bytes = [IO.File]::ReadAllBytes($fontPath)
  $header = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
  $blob = New-Object byte[] ($header.Length + $bytes.Length)
  [Array]::Copy($header, 0, $blob, 0, $header.Length)
  [Array]::Copy($bytes, 0, $blob, $header.Length, $bytes.Length)
  $sha1 = [Security.Cryptography.SHA1]::Create()
  try { $actual = [BitConverter]::ToString($sha1.ComputeHash($blob)).Replace('-','').ToLowerInvariant() } finally { $sha1.Dispose() }
  if (-not [string]::Equals($actual, [string]$fontInfo.sha, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Nerd Font Git blob verification failed.' }
  $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
  New-Item -Path $fontKey -Force | Out-Null
  New-ItemProperty -Path $fontKey -Name 'CaskaydiaCove Nerd Font Mono Regular (TrueType)' -PropertyType String -Value $fontPath -Force | Out-Null
  Write-Output 'CaskaydiaCove Nerd Font installed for this Windows user.'
}

foreach ($tool in @('starship','eza','bat')) {
  if (-not $config.tools.$tool) { continue }
  $toolPath = Join-Path $binDir "${tool}.exe"
  if (-not (Test-Path $toolPath)) {
    try { Install-PortableTool $tool }
    catch { $setupWarnings += "Could not install $tool: $($_.Exception.Message)" }
  } else { Write-Output "$tool is already installed in Ghosty's user bin." }
}

if ($config.tools.starship) {
  try { Install-PortableClink }
  catch { $setupWarnings += "CMD Starship integration unavailable: $($_.Exception.Message)" }
}
if ($config.tools.starship -or $config.tools.eza -or $config.tools.bat) {
  try { Install-GhostyNerdFont }
  catch { $setupWarnings += "Nerd Font install skipped: $($_.Exception.Message)" }
}

$theme = $config.theme
$starshipDir = Join-Path $HOME '.config'
New-Item -ItemType Directory -Force -Path $starshipDir | Out-Null
$starship = @"
format = '$directory$git_branch$character'
[directory]
style = 'bold $($theme.blue)'
truncation_length = 3
[git_branch]
symbol = ' '
style = 'bold $($theme.purple)'
[character]
success_symbol = '[❯](bold $($theme.green))'
error_symbol = '[❯](bold $($theme.red))'
"@
Set-Content -LiteralPath (Join-Path $starshipDir 'starship.toml') -Value $starship -Encoding utf8

$profilePath = $PROFILE
$profileDir = Split-Path -Parent $profilePath
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath | Out-Null }
$profileContents = ''
if (Test-Path $profilePath) {
  $existingProfile = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
  if ($null -ne $existingProfile) { $profileContents = [string]$existingProfile }
}
$block = @'
# >>> Ghosty managed setup >>>
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (&starship init powershell) }
if (Get-Command eza -ErrorAction SilentlyContinue) { function ls { eza --icons @args } }
if (Get-Command bat -ErrorAction SilentlyContinue) { Set-Alias -Name cat -Value bat -Force }
# <<< Ghosty managed setup <<<
'@
$pattern = '(?ms)^# >>> Ghosty managed setup >>>.*?^# <<< Ghosty managed setup <<<\s*'
if ($profileContents -match $pattern) { $profileContents = [regex]::Replace($profileContents, $pattern, '') }
$profileContents = ([string]$profileContents).TrimEnd() + "`r`n`r`n" + $block + "`r`n"
Set-Content -LiteralPath $profilePath -Value $profileContents -Encoding utf8
if ($config.tools.starship -and $clinkReady) {
  $clinkDir = Join-Path $env:LOCALAPPDATA 'clink'
  New-Item -ItemType Directory -Force -Path $clinkDir | Out-Null
  Set-Content -LiteralPath (Join-Path $clinkDir 'ghosty-starship.lua') -Value "load(io.popen('starship init cmd'):read('*a'))" -Encoding utf8
}

# Configure the classic Console Host too (the legacy cmd.exe window does not read Windows Terminal schemes).
$selectedPalette = $config.schemes | Where-Object { $_.name -eq $config.selectedScheme } | Select-Object -First 1
if ($selectedPalette) {
  $consoleKeys = @('HKCU:\Console', 'HKCU:\Console\%SystemRoot%_system32_cmd.exe')
  $colorNames = @('black','red','green','yellow','blue','purple','cyan','white','brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite')
  $validPalette = $true
  foreach ($colorName in $colorNames) {
    $colorValue = [string]$selectedPalette.($colorName)
    if ($colorValue -notmatch '^#[0-9A-Fa-f]{6}$') { $validPalette = $false; break }
  }
  if (-not $validPalette) { $setupWarnings += "The selected palette '$($config.selectedScheme)' is incomplete; console colors were skipped." }
  if ($validPalette) {
    foreach ($key in $consoleKeys) {
      New-Item -Path $key -Force | Out-Null
      for ($i = 0; $i -lt $colorNames.Count; $i++) {
        $hex = ([string]$selectedPalette.($colorNames[$i])).TrimStart('#')
        $r = [Convert]::ToInt32($hex.Substring(0,2),16); $g = [Convert]::ToInt32($hex.Substring(2,2),16); $b = [Convert]::ToInt32($hex.Substring(4,2),16)
        $bgr = [int]($r + ($g -shl 8) + ($b -shl 16))
        New-ItemProperty -Path $key -Name ('ColorTable{0:D2}' -f $i) -PropertyType DWord -Value $bgr -Force | Out-Null
      }
      New-ItemProperty -Path $key -Name ScreenColors -PropertyType DWord -Value 7 -Force | Out-Null
    }
  }
}

# Add persistent doskey shortcuts to new cmd.exe windows without replacing the user's existing AutoRun command.
$cmdMacros = @()
if ($config.tools.eza) { $cmdMacros += 'doskey ls=eza --icons $*' }
if ($config.tools.bat) { $cmdMacros += 'doskey cat=bat $*' }
if ($cmdMacros.Count -gt 0) {
  $cmdKey = 'HKCU:\Software\Microsoft\Command Processor'
  New-Item -Path $cmdKey -Force | Out-Null
  $autoRun = [string]((Get-ItemProperty -Path $cmdKey -Name AutoRun -ErrorAction SilentlyContinue).AutoRun)
  foreach ($macro in $cmdMacros) {
    if ([string]::IsNullOrEmpty($autoRun)) { $autoRun = $macro }
    elseif (-not $autoRun.Contains($macro)) { $autoRun = "$autoRun & $macro" }
  }
  New-ItemProperty -Path $cmdKey -Name AutoRun -PropertyType String -Value $autoRun -Force | Out-Null
}

function Remove-JsonComments([string]$text) {
  $out = [System.Text.StringBuilder]::new()
  $quoted = $false; $escape = $false; $line = $false; $block = $false
  for ($i = 0; $i -lt $text.Length; $i++) {
    $c = $text[$i]; $next = if ($i + 1 -lt $text.Length) { $text[$i+1] } else { [char]0 }
    if ($line) { if ($c -eq "`n" -or $c -eq "`r") { $line = $false; [void]$out.Append($c) }; continue }
    if ($block) { if ($c -eq '*' -and $next -eq '/') { $block = $false; $i++ } elseif ($c -eq "`n" -or $c -eq "`r") { [void]$out.Append($c) }; continue }
    if ($quoted) { [void]$out.Append($c); if ($escape) { $escape = $false } elseif ($c -eq '\') { $escape = $true } elseif ($c -eq '"') { $quoted = $false }; continue }
    if ($c -eq '"') { $quoted = $true; [void]$out.Append($c); continue }
    if ($c -eq '/' -and $next -eq '/') { $line = $true; $i++; continue }
    if ($c -eq '/' -and $next -eq '*') { $block = $true; $i++; continue }
    [void]$out.Append($c)
  }
  return $out.ToString() -replace ',\s*([}\]])', '$1'
}

$settingsCandidates = @(
  (Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'),
  (Join-Path $env:LOCALAPPDATA 'Microsoft/Windows Terminal/settings.json')
)
$settingsPath = $settingsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($settingsPath) {
  $raw = Get-Content -LiteralPath $settingsPath -Raw
  $settings = Remove-JsonComments $raw | ConvertFrom-Json
  $backup = "$settingsPath.ghosty-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Copy-Item -LiteralPath $settingsPath -Destination $backup
  $allSchemes = @($config.schemes)
  $names = @($allSchemes | ForEach-Object { $_.name })
  $existingSchemes = @($settings.schemes | Where-Object { $_ -and $_.name -notin $names })
  if ($settings.PSObject.Properties.Name -contains 'schemes') { $settings.schemes = $existingSchemes + $allSchemes }
  else { $settings | Add-Member -NotePropertyName schemes -NotePropertyValue ($existingSchemes + $allSchemes) }
  if (-not $settings.profiles) { $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = @() }) }
  if (-not $settings.profiles.defaults) { $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force }
  $settings.profiles.defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue $config.selectedScheme -Force
  if (-not $settings.profiles.defaults.font) { $settings.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force }
  $settings.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue 'CaskaydiaCove Nerd Font Mono' -Force
  $json = ConvertTo-Json -InputObject $settings -Depth 100
  Set-Content -LiteralPath $settingsPath -Value $json -Encoding utf8
  Write-Output "Windows Terminal themed: $($config.selectedScheme). Backup: $backup"
} else {
  Write-Output 'Windows Terminal settings not found; installed tools and configured PowerShell, but no Terminal palette was changed.'
}
Write-Output "Ghosty setup applied. Theme: $($config.selectedScheme)."
foreach ($warningMessage in $setupWarnings) { Write-Output "WARNING: $warningMessage" }
# Open a fresh CMD window so the selected colors and AutoRun aliases are visible immediately.
if ($selectedPalette -and $env:ComSpec -and (Test-Path $env:ComSpec)) {
  Start-Process -FilePath $env:ComSpec -WorkingDirectory $HOME -ArgumentList @('/k', 'echo Ghosty setup applied. This window uses your selected theme.')
}

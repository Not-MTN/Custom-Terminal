param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$wingetReady = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$packages = @{ starship = 'Starship.Starship'; eza = 'eza-community.eza'; bat = 'sharkdp.bat' }
$setupWarnings = @()
if (-not $wingetReady) { $setupWarnings += 'WinGet is unavailable. Theme and shell preferences will still be applied; CLI tools were not installed.' }
# Install a Nerd Font so Starship and eza icon glyphs render in terminals.
if ($wingetReady) {
  & winget install --id DEVCOM.CascadiaCodeNerdFont --exact --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { $setupWarnings += "Nerd Font install failed (exit $LASTEXITCODE); theme and tool setup will continue." }
}
$clinkReady = [bool](Get-Command clink -ErrorAction SilentlyContinue)
$clinkMessage = ''
if ($config.tools.starship -and -not $clinkReady -and $wingetReady) {
  Write-Output 'Installing Clink for Starship support in Command Prompt (this package may request administrator approval)...'
  & winget install --id chrisant996.Clink --exact --accept-package-agreements --accept-source-agreements
  $clinkExit = $LASTEXITCODE
  $env:PATH = "$( [Environment]::GetEnvironmentVariable('PATH','Machine') );$( [Environment]::GetEnvironmentVariable('PATH','User') )"
  $clinkReady = [bool](Get-Command clink -ErrorAction SilentlyContinue)
  if (-not $clinkReady) {
    $clinkMessage = "Clink could not be installed or was not available (WinGet exit $clinkExit); Command Prompt will have the theme and selected aliases, but its Starship prompt needs Clink."
    $setupWarnings += $clinkMessage
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
  $binDir = Join-Path $env:LOCALAPPDATA 'Ghosty/bin'
  $tempDir = Join-Path $env:TEMP "ghosty-$tool-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Force -Path $tempDir,$binDir | Out-Null
  $archive = Join-Path $tempDir $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive -UseBasicParsing
  if ($asset.digest -match '^sha256:(.+)$') {
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Matches[1].ToLowerInvariant()) { throw "SHA-256 verification failed for $tool." }
  }
  $extractDir = Join-Path $tempDir 'unpacked'
  Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
  $exe = Get-ChildItem -LiteralPath $extractDir -Filter "$tool.exe" -Recurse | Select-Object -First 1
  if (-not $exe) { throw "$tool.exe was missing from the official release archive." }
  Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $binDir "$tool.exe") -Force
  $userPath = [Environment]::GetEnvironmentVariable('Path','User')
  if (($userPath -split ';') -notcontains $binDir) { [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $binDir).TrimStart(';')), 'User') }
  $env:PATH = "$binDir;$env:PATH"
  Remove-Item -LiteralPath $tempDir -Recurse -Force
  Write-Output "$tool installed from its official portable release."
}

foreach ($tool in @('starship','eza','bat')) {
  if (-not $config.tools.$tool) { continue }
  $installed = [bool](Get-Command "${tool}.exe" -ErrorAction SilentlyContinue)
  if (-not $installed -and $wingetReady) {
    Write-Output "Installing $tool with WinGet..."
    & winget install --id $packages[$tool] --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { $setupWarnings += "WinGet could not install $tool (exit $LASTEXITCODE); trying its official portable release." }
    $env:PATH = "$( [Environment]::GetEnvironmentVariable('PATH','Machine') );$( [Environment]::GetEnvironmentVariable('PATH','User') )"
    $installed = [bool](Get-Command "${tool}.exe" -ErrorAction SilentlyContinue)
  }
  if (-not $installed) {
    try { Install-PortableTool $tool }
    catch { $setupWarnings += "Could not install $tool from its official release: $($_.Exception.Message)" }
  }
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
$profile = Get-Content -LiteralPath $profilePath -Raw
$block = @'
# >>> Ghosty managed setup >>>
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (&starship init powershell) }
if (Get-Command eza -ErrorAction SilentlyContinue) { function ls { eza --icons @args } }
if (Get-Command bat -ErrorAction SilentlyContinue) { Set-Alias -Name cat -Value bat -Force }
# <<< Ghosty managed setup <<<
'@
$pattern = '(?ms)^# >>> Ghosty managed setup >>>.*?^# <<< Ghosty managed setup <<<\s*'
if ($profile -match $pattern) { $profile = [regex]::Replace($profile, $pattern, '') }
$profile = $profile.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
Set-Content -LiteralPath $profilePath -Value $profile -Encoding utf8
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
  foreach ($key in $consoleKeys) {
    New-Item -Path $key -Force | Out-Null
    for ($i = 0; $i -lt $colorNames.Count; $i++) {
      $hex = $selectedPalette.($colorNames[$i]).TrimStart('#')
      $r = [Convert]::ToInt32($hex.Substring(0,2),16); $g = [Convert]::ToInt32($hex.Substring(2,2),16); $b = [Convert]::ToInt32($hex.Substring(4,2),16)
      $bgr = [int]($r + ($g -shl 8) + ($b -shl 16))
      New-ItemProperty -Path $key -Name ('ColorTable{0:D2}' -f $i) -PropertyType DWord -Value $bgr -Force | Out-Null
    }
    New-ItemProperty -Path $key -Name ScreenColors -PropertyType DWord -Value 7 -Force | Out-Null
  }
}

# Add persistent doskey shortcuts to new cmd.exe windows without replacing the user's existing AutoRun command.
$cmdMacros = @()
if ($config.tools.eza) { $cmdMacros += 'doskey ls=eza --icons $*' }
if ($config.tools.bat) { $cmdMacros += 'doskey cat=bat $*' }
if ($cmdMacros.Count -gt 0) {
  $cmdKey = 'HKCU:\Software\Microsoft\Command Processor'
  New-Item -Path $cmdKey -Force | Out-Null
  $autoRun = [string](Get-ItemProperty -Path $cmdKey -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
  foreach ($macro in $cmdMacros) { if (-not $autoRun.Contains($macro)) { $autoRun = (($autoRun, $macro | Where-Object { $_ }) -join ' & ') } }
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
  $settings.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue 'CaskaydiaCove Nerd Font' -Force
  $json = ConvertTo-Json -InputObject $settings -Depth 100
  Set-Content -LiteralPath $settingsPath -Value $json -Encoding utf8
  Write-Output "Windows Terminal themed: $($config.selectedScheme). Backup: $backup"
} else {
  Write-Output 'Windows Terminal settings not found; installed tools and configured PowerShell, but no Terminal palette was changed.'
}
Write-Output "Ghosty setup applied. Theme: $($config.selectedScheme)."
foreach ($warningMessage in $setupWarnings) { Write-Output "WARNING: $warningMessage" }
# Open a fresh CMD window so the selected colors and AutoRun aliases are visible immediately.
if ($selectedPalette) { Start-Process -FilePath $env:ComSpec -ArgumentList @('/k', 'echo Ghosty setup applied. This window uses your selected theme.') }

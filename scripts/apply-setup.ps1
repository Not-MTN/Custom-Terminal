param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'WinGet is required. Install or update App Installer from Microsoft Store, then run Ghosty again.' }
$packages = @{ starship = 'Starship.Starship'; eza = 'eza-community.eza'; bat = 'sharkdp.bat' }
# Install a Nerd Font so Starship and eza icon glyphs render in Windows Terminal.
& winget install --id DEVCOM.CascadiaCodeNerdFont --exact --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "WinGet failed to install Cascadia Code Nerd Font (exit $LASTEXITCODE)." }
foreach ($tool in @('starship','eza','bat')) {
  if ($config.tools.$tool) {
    Write-Output "Installing $tool..."
    & winget install --id $packages[$tool] --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "WinGet failed to install $tool (exit $LASTEXITCODE)." }
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
Write-Output "Ghosty setup applied. Theme: $($config.selectedScheme). Restart PowerShell and Windows Terminal to see changes."

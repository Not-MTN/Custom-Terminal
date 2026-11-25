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
  } finally { if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue } }
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
    } finally { if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue } }
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
  [Array]::Copy($header, 0, $blob, 0, $header.Length); [Array]::Copy($bytes, 0, $blob, $header.Length, $bytes.Length)
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
  if (-not (Test-Path $toolPath)) { try { Install-PortableTool $tool } catch { $setupWarnings += "Could not install ${tool}: $($_.Exception.Message)" } }
  else { Add-GhostyBinToPath $binDir; Write-Output "$tool is already installed in Ghosty's user bin." }
}
if ($config.tools.starship) { try { Install-PortableClink } catch { $setupWarnings += "CMD Starship integration unavailable: $($_.Exception.Message)" } }
if ($config.tools.starship -or $config.tools.eza -or $config.tools.bat) { try { Install-GhostyNerdFont } catch { $setupWarnings += "Nerd Font install skipped: $($_.Exception.Message)" } }

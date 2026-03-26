# Package tmmaps plugin and install to OpenPlanet Plugins folder.
# Run from repo root: .\package-and-install.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$PluginsDir = "C:\Users\fanto\OpenplanetNext\Plugins"
$OutputName = "tmmaps.op"

# Files to include (info.toml + all .as, including v3 subfolder)
$fileMap = @{}
$fileMap["info.toml"] = Join-Path $RepoRoot "info.toml"
Get-ChildItem -Path $RepoRoot -Filter "*.as" -File | ForEach-Object { $fileMap[$_.Name] = $_.FullName }
$v3Dir = Join-Path $RepoRoot "v3"
if (Test-Path $v3Dir) {
    Get-ChildItem -Path $v3Dir -Filter "*.as" -File | ForEach-Object { $fileMap[$_.Name] = $_.FullName }
}
$v4Dir = Join-Path $RepoRoot "v4"
if (Test-Path $v4Dir) {
    Get-ChildItem -Path $v4Dir -Filter "*.as" -File | ForEach-Object { $fileMap[$_.Name] = $_.FullName }
}

# Build zip with flat structure (all .as at root for OpenPlanet)
$opPath  = Join-Path $RepoRoot $OutputName
$zipPath = Join-Path $RepoRoot ($OutputName -replace '\.op$', '.zip')
if (Test-Path $opPath)  { Remove-Item $opPath  -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$tempDir = Join-Path $env:TEMP "tmmaps_package"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

foreach ($name in $fileMap.Keys) {
    Copy-Item $fileMap[$name] (Join-Path $tempDir $name) -Force
}

Compress-Archive -Path (Join-Path $tempDir "*") -DestinationPath $zipPath -Force
Remove-Item $tempDir -Recurse -Force
Rename-Item -Path $zipPath -NewName $OutputName

# Copy to Plugins, overwriting
$dest = Join-Path $PluginsDir $OutputName
if (-not (Test-Path $PluginsDir)) {
    Write-Error "Plugins folder not found: $PluginsDir"
}
Copy-Item $opPath $dest -Force

Write-Host "Done: $OutputName -> $dest"

# PowerShell script to package the AdGuardHome Magisk module
param(
    [string]$Architecture = "arm64"
)

# Create cache directory if it doesn't exist
if (!(Test-Path "cache")) {
    New-Item -ItemType Directory -Path "cache" -Force
}

# Get the latest AdGuardHome version from GitHub API
$apiUrl = "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
$response = Invoke-RestMethod -Uri $apiUrl -Method Get
$version = $response.tag_name
$assets = $response.assets

# Find the appropriate asset for the architecture
$asset = $assets | Where-Object { $_.name -like "*linux_${Architecture}.tar.gz" }

if ($null -eq $asset) {
    Write-Error "No AdGuardHome asset found for architecture: $Architecture"
    exit 1
}

$downloadUrl = $asset.browser_download_url
$assetName = $asset.name

# Set file paths
$cachePath = Join-Path "cache" $assetName
$destPath = Join-Path "cache" "AdGuardHome"

# Download AdGuardHome if not in cache or version changed
if (!(Test-Path $cachePath)) {
    Write-Host "Downloading AdGuardHome from: $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $cachePath
}

# Extract AdGuardHome binary
$extractPath = Join-Path "cache" "extracted"
if (Test-Path $extractPath) {
    Remove-Item -Path $extractPath -Recurse -Force
}
New-Item -ItemType Directory -Path $extractPath -Force

# Use tar to extract (PowerShell 5.1+ has tar available by default on Windows 10+)
tar -xzf $cachePath -C $extractPath

# Copy the AdGuardHome binary to src/bin
$sourceBinary = Join-Path $extractPath "AdGuardHome"
$destBinary = Join-Path "src" "bin" "AdGuardHome"

if (Test-Path $destBinary) {
    Remove-Item -Path $destBinary -Force
}

Copy-Item -Path $sourceBinary -Destination $destBinary -Force
Set-ItemProperty -Path $destBinary -Name IsReadOnly -Value $false

# Update version in module.prop
$modulePropPath = Join-Path "src" "module.prop"
$versionCode = Get-Date -Format "yyyyMMdd"
$moduleContent = Get-Content $modulePropPath
$moduleContent = $moduleContent -replace "^version=.*", "version=$($version.TrimStart('v'))"
$moduleContent = $moduleContent -replace "^versionCode=.*", "versionCode=$versionCode"
Set-Content -Path $modulePropPath -Value $moduleContent

Write-Host "Updated module.prop with version $($version.TrimStart('v')) and versionCode $versionCode"

# Update version.json
$versionJsonPath = Join-Path "src" "version.json"
$versionJson = Get-Content $versionJsonPath | ConvertFrom-Json
$versionJson.version = $version.TrimStart('v')
$versionJson.versionCode = [int]$versionCode
$versionJson | ConvertTo-Json -Depth 10 | Set-Content $versionJsonPath

# Create module zip
$moduleName = "AdGuardHomeForRoot_$Architecture"
$zipPath = "$moduleName.zip"

# Create a temporary directory for packaging
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "AdGuardHomeModuleTemp"
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force

# Copy src directory contents to temp directory
Copy-Item -Path "src" -Destination $tempDir -Recurse -Container

# Remove the update_adh.sh from the module as it's not needed in the final package
$tempUpdateScript = Join-Path $tempDir "src" "update_adh.sh"
if (Test-Path $tempUpdateScript) {
    Remove-Item -Path $tempUpdateScript -Force
}

# Create the zip file
$srcDir = Join-Path $tempDir "src"
Compress-Archive -Path $srcDir -DestinationPath $zipPath -Force

Write-Host "Module packaged as: $zipPath"
Write-Host "Version: $($version.TrimStart('v'))"
Write-Host "Version Code: $versionCode"

# Cleanup
Remove-Item -Path $tempDir -Recurse -Force

Write-Host "Packaging complete!"
# CY-CLI Windows Installer with Self-Updating Wrapper
# Installs cy-wrapper.ps1 which auto-updates the real binary from GitHub Releases

param(
    [string]$InstallDir = "$env:USERPROFILE\.local\bin",
    [string]$Repo = "SYMBIOTYC/cy-cli",
    [string]$StoreDir = "$env:USERPROFILE\.local\share\cy"
)

$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# Detect architecture
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "x86_64" }
    "ARM64" { "aarch64" }
    default { Write-Err "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}

$triple = "$arch-pc-windows-msvc"
$asset = "cy-${triple}.zip"

Write-Info "CY-CLI Windows Installer (self-updating)"
Write-Info "Architecture: $arch ($triple)"

# Determine version
if ($env:CY_VERSION) {
    $version = $env:CY_VERSION
} else {
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Method Get
        $version = $release.tag_name.TrimStart('v')
    } catch {
        Write-Err "Could not determine latest release. Is the repo public? Specify CY_VERSION env var for private repos."
    }
}

Write-Info "Version: $version"

$baseUrl = "https://github.com/$Repo/releases/download/v$version"
$assetUrl = "$baseUrl/$asset"

$tmpdir = Join-Path $env:TEMP "cy-install-$(New-Guid)"
New-Item -ItemType Directory -Path $tmpdir -Force | Out-Null
trap { Remove-Item -Recurse -Force $tmpdir }

# Download
Write-Info "Downloading $asset..."
Invoke-WebRequest -Uri $assetUrl -OutFile (Join-Path $tmpdir $asset) -UseBasicParsing

# Extract
Write-Info "Extracting..."
Expand-Archive -Path (Join-Path $tmpdir $asset) -DestinationPath $tmpdir -Force

# Install initial binary to store dir
Write-Info "Installing initial binary to $StoreDir\bin..."
New-Item -ItemType Directory -Path (Join-Path $StoreDir "bin") -Force | Out-Null
$cyExe = Join-Path $tmpdir "cy.exe"
if (-not (Test-Path $cyExe)) {
    $cyExe = Join-Path $tmpdir "cy"
}
Copy-Item $cyExe (Join-Path $StoreDir "bin\cy.exe") -Force
Set-Content -Path (Join-Path $StoreDir "VERSION") -Value $version

# Install wrapper
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wrapperSrc = Join-Path $scriptDir "cy-wrapper.ps1"

Write-Info "Installing self-updating wrapper to $InstallDir\cy.ps1..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item $wrapperSrc (Join-Path $InstallDir "cy.ps1") -Force

# Create a .cmd shim so 'cy' works from cmd.exe too
$cmdShim = "@echo off`r`npowershell -ExecutionPolicy Bypass -File `"%USERPROFILE%\.local\bin\cy.ps1`" %*"
Set-Content -Path (Join-Path $InstallDir "cy.cmd") -Value $cmdShim -Encoding ASCII

Write-Info "Installed cy to $InstallDir\cy.ps1 (and cy.cmd shim)"
Write-Info "Binary stored at $StoreDir\bin\cy.exe"

# Check PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$InstallDir*") {
    Write-Warn "$InstallDir is not in your PATH."
    Write-Warn "Add it by running:"
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `$env:Path + ';$InstallDir', 'User')"
}

# Verify
Write-Info "Verifying..."
& powershell -ExecutionPolicy Bypass -File (Join-Path $InstallDir "cy.ps1") --version

Write-Info "Installation complete! cy will auto-update on each launch."

# CY-CLI Windows Installer
# Detects arch, downloads the right binary, installs to $env:USERPROFILE\.cy\bin

param(
    [string]$InstallDir = "$env:USERPROFILE\.cy\bin",
    [string]$Repo = "vladleopold/cy-cli"
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

Write-Info "CY-CLI Windows Installer"
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
$checksumsUrl = "$baseUrl/SHA256SUMS"

$tmpdir = Join-Path $env:TEMP "cy-install-$(New-Guid)"
New-Item -ItemType Directory -Path $tmpdir -Force | Out-Null
trap { Remove-Item -Recurse -Force $tmpdir }

# Download
Write-Info "Downloading $asset..."
Invoke-WebRequest -Uri $assetUrl -OutFile (Join-Path $tmpdir $asset) -UseBasicParsing

# Download checksums
Write-Info "Downloading checksums..."
try {
    Invoke-WebRequest -Uri $checksumsUrl -OutFile (Join-Path $tmpdir "SHA256SUMS") -UseBasicParsing
} catch {
    Write-Warn "Could not download checksums, skipping verification"
}

# Verify checksum
$zipPath = Join-Path $tmpdir $asset
if (Test-Path (Join-Path $tmpdir "SHA256SUMS")) {
    $expected = (Get-Content (Join-Path $tmpdir "SHA256SUMS") | Select-String $asset | ForEach-Object { $_.Line.Split()[0] })
    if ($expected) {
        $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if ($hash -ne $expected) {
            Write-Err "Checksum verification failed. Expected: $expected, Got: $hash"
        }
        Write-Info "Checksum verified"
    }
}

# Extract
Write-Info "Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $tmpdir -Force

# Install
Write-Info "Installing to $InstallDir..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item (Join-Path $tmpdir "cy.exe") (Join-Path $InstallDir "cy.exe") -Force

Write-Info "Installed cy.exe to $InstallDir\cy.exe"

# Check PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$InstallDir*") {
    Write-Warn "$InstallDir is not in your PATH."
    Write-Warn "Add it by running:"
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `$env:Path + ';$InstallDir', 'User')"
}

# Verify
Write-Info "Verifying installation..."
& "$InstallDir\cy.exe" --version

Write-Info "Installation complete!"

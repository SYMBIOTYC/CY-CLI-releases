#!/usr/bin/env bash
set -euo pipefail

# CY-CLI Installer
# Detects OS/arch, downloads the right binary, installs to ~/.local/bin

REPO="vladleopold/cy-cli"
INSTALL_DIR="${CY_INSTALL_DIR:-$HOME/.local/bin}"
BINARY_NAME="cy"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

# Detect OS
detect_os() {
  case "$(uname -s)" in
    Linux*)     echo "linux";;
    Darwin*)    echo "macos";;
    *)          err "Unsupported OS: $(uname -s)"; exit 1;;
  esac
}

# Detect architecture
detect_arch() {
  case "$(uname -m)" in
    x86_64)     echo "x86_64";;
    aarch64|arm64) echo "aarch64";;
    *)          err "Unsupported architecture: $(uname -m)"; exit 1;;
  esac
}

# Map OS to target triple
target_triple() {
  local os="$1" arch="$2"
  case "$os-$arch" in
    linux-x86_64)    echo "x86_64-unknown-linux-gnu";;
    linux-aarch64)   echo "aarch64-unknown-linux-gnu";;
    macos-x86_64)    echo "x86_64-apple-darwin";;
    macos-aarch64)   echo "aarch64-apple-darwin";;
    *)               err "Unsupported target: $os-$arch"; exit 1;;
  esac
}

# Get latest release tag from GitHub API
get_latest_tag() {
  local tag
  tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  if [ -z "$tag" ]; then
    err "Could not determine latest release. Is the repo public? For private repos, specify CY_VERSION env var."
    exit 1
  fi
  echo "$tag"
}

# Download file with progress
download() {
  local url="$1" output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
  else
    err "Neither curl nor wget found. Please install one of them."
    exit 1
  fi
}

# Verify checksum
verify_checksum() {
  local file="$1" sums_file="$2"
  if [ -f "$sums_file" ]; then
    local expected
    expected=$(grep "$(basename "$file")" "$sums_file" | awk '{print $1}')
    if [ -n "$expected" ]; then
      local actual
      actual=$(sha256sum "$file" | awk '{print $1}')
      if [ "$actual" != "$expected" ]; then
        err "Checksum verification failed for $(basename "$file")"
        err "Expected: $expected"
        err "Actual:   $actual"
        exit 1
      fi
      info "Checksum verified"
    fi
  else
    warn "No checksums file found, skipping verification"
  fi
}

main() {
  info "CY-CLI Installer"

  local os arch triple version asset_file asset_url sums_url binary_name

  os=$(detect_os)
  arch=$(detect_arch)
  triple=$(target_triple "$os" "$arch")

  # Allow version override
  if [ -n "${CY_VERSION:-}" ]; then
    version="$CY_VERSION"
  else
    version=$(get_latest_tag)
  fi
  version="${version#v}" # strip leading v

  info "OS: $os, Arch: $arch, Target: $triple"
  info "Version: $version"

  # Determine asset names
  if [ "$os" = "windows" ]; then
    asset_file="cy-${triple}.zip"
    binary_name="cy.exe"
  else
    asset_file="cy-${triple}.tar.gz"
    binary_name="cy"
  fi

  local base_url="https://github.com/$REPO/releases/download/v$version"
  asset_url="$base_url/$asset_file"
  sums_url="$base_url/SHA256SUMS"

  # Create temp directory
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT

  # Download
  info "Downloading $asset_file..."
  download "$asset_url" "$tmpdir/$asset_file"

  # Download checksums
  info "Downloading checksums..."
  download "$sums_url" "$tmpdir/SHA256SUMS" || true

  # Verify
  verify_checksum "$tmpdir/$asset_file" "$tmpdir/SHA256SUMS"

  # Extract
  info "Extracting..."
  cd "$tmpdir"
  if [ "$os" = "windows" ]; then
    unzip -q "$asset_file"
  else
    tar xzf "$asset_file"
  fi

  # Install
  info "Installing to $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR"
  cp "$tmpdir/$binary_name" "$INSTALL_DIR/$binary_name"
  chmod +x "$INSTALL_DIR/$binary_name"

  info "Installed $BINARY_NAME to $INSTALL_DIR/$binary_name"

  # Check PATH
  if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    warn "$INSTALL_DIR is not in your PATH."
    warn "Add it to your PATH by adding this line to your shell rc file:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
  fi

  # Verify
  info "Verifying installation..."
  "$INSTALL_DIR/$binary_name" --version || true

  info "Installation complete!"
}

main "$@"

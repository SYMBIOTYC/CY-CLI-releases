#!/usr/bin/env bash
set -euo pipefail

# CY-CLI Installer with Self-Updating Wrapper
# Installs cy-wrapper.sh which auto-updates the real binary from GitHub Releases

REPO="SYMBIOTYC/CY-CLI"
INSTALL_DIR="${CY_INSTALL_DIR:-$HOME/.local/bin}"
CY_STORE_DIR="${CY_STORE_DIR:-$HOME/.local/share/cy}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux";;
    Darwin*) echo "macos";;
    *)       err "Unsupported OS: $(uname -s)"; exit 1;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64)    echo "x86_64";;
    aarch64|arm64) echo "aarch64";;
    *)         err "Unsupported architecture: $(uname -m)"; exit 1;;
  esac
}

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

get_latest_tag() {
  curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' \
    | sed -E 's/.*"([^"]+)".*/\1/' \
    | head -1
}

download() {
  local url="$1" output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
  else
    err "Neither curl nor wget found."
    exit 1
  fi
}

install_wrapper() {
  local wrapper_src="$1"
  info "Installing self-updating wrapper to ${INSTALL_DIR}/cy"
  mkdir -p "$INSTALL_DIR"
  cp "$wrapper_src" "$INSTALL_DIR/cy"
  chmod +x "$INSTALL_DIR/cy"
}

install_initial_binary() {
  local os="$1" arch="$2" triple="$3"
  local tag="$4"
  local asset_file="cy-${triple}.tar.gz"
  
  local base_url="https://github.com/$REPO/releases/download/${tag}"
  local asset_url="$base_url/$asset_file"
  
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  
  info "Downloading initial binary ${tag}..."
  download "$asset_url" "$tmpdir/$asset_file"
  
  info "Extracting to ${CY_STORE_DIR}/bin..."
  mkdir -p "${CY_STORE_DIR}/bin"
  tar xzf "$tmpdir/$asset_file" -C "$tmpdir"
  cp "$tmpdir/cy" "${CY_STORE_DIR}/bin/cy"
  chmod +x "${CY_STORE_DIR}/bin/cy"
  
  echo "${tag#v}" > "${CY_STORE_DIR}/VERSION"
}

main() {
  info "CY-CLI Installer (self-updating)"
  
  local os arch triple version tag
  
  os=$(detect_os)
  arch=$(detect_arch)
  triple=$(target_triple "$os" "$arch")
  
  if [ -n "${CY_VERSION:-}" ]; then
    tag="v${CY_VERSION#v}"
  else
    tag=$(get_latest_tag)
  fi
  
  if [ -z "$tag" ]; then
    err "Could not determine release tag"
    exit 1
  fi
  
  info "Target: $os/$arch ($triple)"
  info "Version: $tag"
  
  # Determine wrapper location (next to this script)
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local wrapper_src="${script_dir}/../tools/cy-wrapper.sh"
  
  if [ ! -f "$wrapper_src" ]; then
    err "cy-wrapper.sh not found at ${wrapper_src}"
    exit 1
  fi
  
  # Install wrapper
  install_wrapper "$wrapper_src"
  
  # Install initial binary so wrapper has something to run on first launch
  install_initial_binary "$os" "$arch" "$triple" "$tag"
  
  info "Installed cy to ${INSTALL_DIR}/cy"
  info "Binary stored at ${CY_STORE_DIR}/bin/cy"
  
  # Check PATH
  if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    warn "$INSTALL_DIR is not in your PATH."
    warn "Add it: export PATH=\"$INSTALL_DIR:\$PATH\""
  fi
  
  # Verify
  info "Verifying..."
  "$INSTALL_DIR/cy" --version || true
  
  info "Installation complete! cy will auto-update on each launch."
}

main "$@"

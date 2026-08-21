#!/usr/bin/env bash
set -euo pipefail

# CY-CLI Self-Updating Wrapper
# Проверяет обновления на GitHub Releases и автоматически обновляет бинарник.

CY_REPO="${CY_REPO:-SYMBIOTYC/CY-CLI}"
CY_INSTALL_DIR="${CY_INSTALL_DIR:-${HOME}/.local/share/cy}"
CY_VERSION_FILE="${CY_INSTALL_DIR}/VERSION"
CY_BIN_DIR="${CY_INSTALL_DIR}/bin"

mkdir -p "${CY_BIN_DIR}"

detect_target() {
  local arch
  arch=$(get_arch)
  case "$(uname -s)" in
    Linux*)
      case "$arch" in
        x86_64)   echo "x86_64-unknown-linux-gnu" ;;
        aarch64)  echo "aarch64-unknown-linux-gnu" ;;
        *)        echo "x86_64-unknown-linux-gnu" ;;
      esac
      ;;
    Darwin*)
      case "$arch" in
        x86_64)   echo "x86_64-apple-darwin" ;;
        aarch64)  echo "aarch64-apple-darwin" ;;
        *)        echo "x86_64-apple-darwin" ;;
      esac
      ;;
    *)       echo "x86_64-unknown-linux-gnu" ;;
  esac
}

get_arch() {
  case "$(uname -m)" in
    x86_64)   echo "x86_64" ;;
    aarch64)  echo "aarch64" ;;
    arm64)    echo "aarch64" ;;
    *)        echo "x86_64" ;;
  esac
}

get_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    *)       echo "linux" ;;
  esac
}

get_latest_tag() {
  curl -fsSL "https://api.github.com/repos/${CY_REPO}/releases/latest" \
    | grep '"tag_name"' \
    | sed -E 's/.*"([^"]+)".*/\1/' \
    | head -1
}

get_local_version() {
  if [ -f "${CY_VERSION_FILE}" ]; then
    cat "${CY_VERSION_FILE}"
  else
    echo ""
  fi
}

download_and_install() {
  local tag="$1"
  local target="$2"
  local arch="$3"
  local os="$4"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf ${tmpdir}" EXIT

  local asset_name="cy-${target}"
  if [ "${os}" = "linux" ] || [ "${os}" = "macos" ]; then
    asset_name="cy-${target}.tar.gz"
  else
    asset_name="cy-${target}.zip"
  fi

  local url="https://github.com/${CY_REPO}/releases/download/${tag}/${asset_name}"
  local output="${tmpdir}/${asset_name}"

  echo "[cy-wrapper] Downloading ${asset_name}..." >&2
  curl -fL --progress-bar -o "${output}" "${url}"

  if [ "${os}" = "linux" ] || [ "${os}" = "macos" ]; then
    tar xzf "${output}" -C "${tmpdir}"
    cp "${tmpdir}/cy" "${CY_BIN_DIR}/cy"
    chmod +x "${CY_BIN_DIR}/cy"
  else
    unzip -q "${output}" -d "${tmpdir}"
    cp "${tmpdir}/cy.exe" "${CY_BIN_DIR}/cy.exe"
  fi

  echo "${tag#v}" > "${CY_VERSION_FILE}"
  echo "[cy-wrapper] Installed ${tag}" >&2
}

update_if_needed() {
  local target
  target=$(detect_target)
  local arch
  arch=$(get_arch)
  local os
  os=$(get_os)

  local latest_tag
  latest_tag=$(get_latest_tag) || {
    echo "[cy-wrapper] Failed to fetch latest release, using cached version" >&2
    return 0
  }

  if [ -z "${latest_tag}" ]; then
    echo "[cy-wrapper] No releases found" >&2
    return 0
  fi

  local local_version
  local_version=$(get_local_version)

  if [ "${local_version}" != "${latest_tag#v}" ]; then
    echo "[cy-wrapper] Update available: ${local_version:-none} -> ${latest_tag}" >&2
    download_and_install "${latest_tag}" "${target}" "${arch}" "${os}"
  fi
}

find_fallback_cy() {
  # If no managed binary exists, try to find cy in PATH
  if [ -x "${CY_BIN_DIR}/cy" ]; then
    echo "${CY_BIN_DIR}/cy"
    return 0
  fi
  
  local fallback
  fallback=$(command -v cy 2>/dev/null || true)
  if [ -n "$fallback" ]; then
    echo "$fallback"
    return 0
  fi
  
  return 1
}

main() {
  update_if_needed

  local cy_binary
  cy_binary=$(find_fallback_cy) || {
    echo "[cy-wrapper] No cy binary found. Please run install script first." >&2
    exit 1
  }

  exec "$cy_binary" "$@"
}

main "$@"

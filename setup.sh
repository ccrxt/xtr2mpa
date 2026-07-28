#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${SCRIPT_DIR}/bin:${HOME}/.local/bin:${PATH}"

need_command() {
  local name="$1"
  local install_hint="$2"

  if ! command -v "$name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$name" >&2
    printf '%s\n' "$install_hint" >&2
    exit 1
  fi
}

install_ffmpeg_macos() {
  if command -v brew >/dev/null 2>&1; then
    printf 'Installing FFmpeg for macOS with Homebrew...\n'
    if brew install ffmpeg; then
      return 0
    fi
  fi
  printf 'Homebrew not available or failed. Falling back to static binary download...\n'
  install_ffmpeg_static
}

can_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    return 0
  fi
  return 1
}

run_apt_get() {
  if [ "$(id -u)" -eq 0 ]; then
    apt-get "$@"
  else
    sudo -n apt-get "$@"
  fi
}

install_ffmpeg_ubuntu() {
  if can_sudo; then
    printf 'Installing FFmpeg for Ubuntu/Debian with apt-get...\n'
    if run_apt_get update && run_apt_get install -y ffmpeg; then
      return 0
    fi
    printf 'apt-get installation failed.\n' >&2
  else
    printf 'Root/sudo access not available without interactive password.\n' >&2
  fi
  printf 'Falling back to downloading static FFmpeg binaries...\n'
  install_ffmpeg_static
}

install_ffmpeg_static() {
  local target_dir="${SCRIPT_DIR}/bin"
  mkdir -p "$target_dir"
  printf 'Downloading static FFmpeg binaries into %s...\n' "$target_dir"

  local os_name
  local arch_name
  os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch_name="$(uname -m)"

  local platform=""
  case "$os_name" in
    linux)
      case "$arch_name" in
        x86_64|amd64)
          platform="linux-64"
          ;;
        aarch64|arm64)
          platform="linux-arm64"
          ;;
        armv7l|armhf)
          platform="linux-armhf"
          ;;
        *)
          platform="linux-32"
          ;;
      esac
      ;;
    darwin)
      platform="osx-64"
      ;;
    *)
      printf 'Unsupported operating system for static binary download: %s\n' "$os_name" >&2
      return 1
      ;;
  esac

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$platform" "$target_dir" <<'PYEOF'
import sys, urllib.request, zipfile, io, os, stat

platform = sys.argv[1]
target_dir = sys.argv[2]

urls = [
    f"https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffmpeg-4.4.1-{platform}.zip",
    f"https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffprobe-4.4.1-{platform}.zip"
]

for url in urls:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp:
        content = resp.read()
    with zipfile.ZipFile(io.BytesIO(content)) as z:
        z.extractall(target_dir)

for binary in ['ffmpeg', 'ffprobe']:
    path = os.path.join(target_dir, binary)
    if os.path.exists(path):
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PYEOF
  elif command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
    local url_ffmpeg="https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffmpeg-4.4.1-${platform}.zip"
    local url_ffprobe="https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffprobe-4.4.1-${platform}.zip"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    curl -sSL "$url_ffmpeg" -o "$tmp_dir/ffmpeg.zip"
    curl -sSL "$url_ffprobe" -o "$tmp_dir/ffprobe.zip"
    unzip -o "$tmp_dir/ffmpeg.zip" -d "$target_dir"
    unzip -o "$tmp_dir/ffprobe.zip" -d "$target_dir"
    chmod +x "$target_dir/ffmpeg" "$target_dir/ffprobe"
  else
    printf 'Error: Neither python3 nor (curl + unzip) is available to download static binaries.\n' >&2
    return 1
  fi
}

if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
  printf 'FFmpeg is already installed.\n'
  ffmpeg -version | sed -n '1p'
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    install_ffmpeg_macos
    ;;
  Linux)
    if [ -r /etc/os-release ] && grep -qiE 'ubuntu|debian' /etc/os-release; then
      install_ffmpeg_ubuntu
    else
      printf 'System package manager auto-install is unsupported on this Linux distribution.\n'
      printf 'Falling back to downloading static FFmpeg binaries...\n'
      install_ffmpeg_static
    fi
    ;;
  *)
    printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2
    printf 'Falling back to downloading static FFmpeg binaries...\n'
    install_ffmpeg_static
    ;;
esac

need_command "ffmpeg" "FFmpeg installation finished, but ffmpeg was not found in PATH."
need_command "ffprobe" "FFmpeg installation finished, but ffprobe was not found in PATH."

printf 'Setup complete.\n'
ffmpeg -version | sed -n '1p'


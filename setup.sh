#!/usr/bin/env bash
set -euo pipefail

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
  need_command "brew" "Install Homebrew first: https://brew.sh/"
  brew install ffmpeg
}

install_ffmpeg_ubuntu() {
  need_command "apt-get" "This setup script supports Ubuntu/Debian apt-get for Linux installs."

  if [ "$(id -u)" -eq 0 ]; then
    apt-get update
    apt-get install -y ffmpeg
  else
    need_command "sudo" "Install sudo or run this script as root."
    sudo apt-get update
    sudo apt-get install -y ffmpeg
  fi
}

if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
  printf 'FFmpeg is already installed.\n'
  ffmpeg -version | sed -n '1p'
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    printf 'Installing FFmpeg for macOS with Homebrew...\n'
    install_ffmpeg_macos
    ;;
  Linux)
    if [ -r /etc/os-release ] && grep -qiE 'ubuntu|debian' /etc/os-release; then
      printf 'Installing FFmpeg for Ubuntu/Debian with apt-get...\n'
      install_ffmpeg_ubuntu
    else
      printf 'Unsupported Linux distribution for automatic setup.\n' >&2
      printf 'Install FFmpeg with your package manager, then run ./extract.sh.\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2
    printf 'Install FFmpeg manually, then run ./extract.sh.\n' >&2
    exit 1
    ;;
esac

need_command "ffmpeg" "FFmpeg installation finished, but ffmpeg was not found in PATH."
need_command "ffprobe" "FFmpeg installation finished, but ffprobe was not found in PATH."

printf 'Setup complete.\n'
ffmpeg -version | sed -n '1p'

#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y \
  git curl wget python3 python3-venv python3-pip python3-pexpect python3-serial \
  build-essential cmake ninja-build pkg-config ccache \
  libssl-dev libzstd-dev zlib1g-dev libpixman-1-dev libfdt-dev \
  libglib2.0-dev libslirp-dev \
  device-tree-compiler u-boot-tools mtools parted gdisk \
  flex bison gettext \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  libsdl2-dev sshpass netcat-openbsd
if ! command -v repo >/dev/null 2>&1; then
  sudo curl -o /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
  sudo chmod +x /usr/local/bin/repo
fi
echo "[deps] ok"

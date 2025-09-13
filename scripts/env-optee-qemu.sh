#!/usr/bin/env bash
# 统一环境：仅 arm64 TA DevKit
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPTEE_ROOT="$REPO_ROOT/third_party/optee"
export OPTEE_BUILD_DIR="$OPTEE_ROOT/build"
export TA_DEV_KIT_DIR="$OPTEE_ROOT/optee_os/out/arm/export-ta_arm64"
export OPTEE_OS_EXPORT="$TA_DEV_KIT_DIR"
export OPTEE_CLIENT_EXPORT="$REPO_ROOT/third_party/optee/optee_client/out/export/usr"
export TEEC_INCLUDE_DIR="$OPTEE_CLIENT_EXPORT/include"
export TEEC_LIB="$OPTEE_CLIENT_EXPORT/lib/libteec.a"
export QEMU_SSH_PORT="${QEMU_SSH_PORT:-2222}"
export QEMU_GUEST_USER="${QEMU_GUEST_USER:-root}"
export QEMU_GUEST_PASS="${QEMU_GUEST_PASS:-root}"
export CROSS_COMPILE=aarch64-linux-gnu-

#!/usr/bin/env bash
# Common environment for OP-TEE qemu-v8
export BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPTEE_BUILD_DIR="${BASEDIR}/third_party/optee_build"
export OPTEE_OS_EXPORT="${OPTEE_BUILD_DIR}/optee_os/out/arm/export-ta_arm64"
export TA_DEV_KIT_DIR="${OPTEE_OS_EXPORT}"
export CROSS_COMPILE=aarch64-linux-gnu-
export QEMU_SSH_PORT=10022
export QEMU_GUEST_USER=root
export QEMU_GUEST_PASS=root

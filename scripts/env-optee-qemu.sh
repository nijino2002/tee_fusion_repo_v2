#!/usr/bin/env bash
# 统一环境：仅 arm64 TA DevKit
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPTEE_ROOT="$REPO_ROOT/third_party/optee"
export OPTEE_BUILD_DIR="$OPTEE_ROOT/build"
export TA_DEV_KIT_DIR="$OPTEE_ROOT/optee_os/out/arm/export-ta_arm64"
export OPTEE_OS_EXPORT="$TA_DEV_KIT_DIR"

# 动态解析 OPTEE_CLIENT_EXPORT，允许外部覆盖
if [[ -z "${OPTEE_CLIENT_EXPORT:-}" ]]; then
  BR_SYSROOT_USR="$REPO_ROOT/third_party/optee/out-br/host/aarch64-buildroot-linux-gnu/sysroot/usr"
  if [[ -f "$BR_SYSROOT_USR/include/tee_client_api.h" ]] && \
     ([[ -f "$BR_SYSROOT_USR/lib/libteec.so" ]] || [[ -f "$BR_SYSROOT_USR/lib/libteec.a" ]]); then
    export OPTEE_CLIENT_EXPORT="$BR_SYSROOT_USR"
  else
    CAND1="$REPO_ROOT/third_party/optee/optee_client/out/export/usr"
    CAND2="$REPO_ROOT/third_party/optee/build/optee_client/out/export/usr"
    if [[ -f "$CAND1/include/tee_client_api.h" ]] && \
       ([[ -f "$CAND1/lib/libteec.so" ]] || [[ -f "$CAND1/lib/libteec.a" ]]); then
      export OPTEE_CLIENT_EXPORT="$CAND1"
    elif [[ -f "$CAND2/include/tee_client_api.h" ]] && \
         ([[ -f "$CAND2/lib/libteec.so" ]] || [[ -f "$CAND2/lib/libteec.a" ]]); then
      export OPTEE_CLIENT_EXPORT="$CAND2"
    else
      export OPTEE_CLIENT_EXPORT=""
    fi
  fi
fi

if [[ -n "${OPTEE_CLIENT_EXPORT}" ]]; then
  export TEEC_INCLUDE_DIR="$OPTEE_CLIENT_EXPORT/include"
  if [[ -f "$OPTEE_CLIENT_EXPORT/lib/libteec.a" ]]; then
    export TEEC_LIB="$OPTEE_CLIENT_EXPORT/lib/libteec.a"
  else
    export TEEC_LIB="$OPTEE_CLIENT_EXPORT/lib/libteec.so"
  fi
fi
# Default SSH host port (OP-TEE docs use 10022)
export QEMU_SSH_PORT="${QEMU_SSH_PORT:-10022}"
export QEMU_GUEST_USER="${QEMU_GUEST_USER:-root}"
export QEMU_GUEST_PASS="${QEMU_GUEST_PASS:-root}"
export CROSS_COMPILE=aarch64-linux-gnu-

#!/usr/bin/env bash
set -euo pipefail

# Load env and resolve paths
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/env-optee-qemu.sh"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

has_teec() {
  local base="$1"
  [[ -n "$base" ]] || return 1
  [[ -f "$base/include/tee_client_api.h" ]] || return 1
  [[ -f "$base/lib/libteec.so" || -f "$base/lib/libteec.a" ]]
}

# Default candidates
OPTEE_CLIENT_EXPORT="${OPTEE_CLIENT_EXPORT:-}"
if [[ -z "${OPTEE_CLIENT_EXPORT}" ]]; then
  OPTEE_CLIENT_EXPORT="$REPO_ROOT/third_party/optee/optee_client/out/export/usr"
fi

# Try to locate Buildroot aarch64 sysroot for OpenSSL and TEEC
BR_SYSROOT_USR="$REPO_ROOT/third_party/optee/out-br/host/aarch64-buildroot-linux-gnu/sysroot/usr"
if [[ -z "${FORCE_HOST_TEEC:-}" ]] && has_teec "$BR_SYSROOT_USR"; then
  echo "[tc] Using TEE Client from Buildroot sysroot: $BR_SYSROOT_USR"
  OPTEE_CLIENT_EXPORT="$BR_SYSROOT_USR"
fi

# If still invalid, try alternate path from OP-TEE build tree
if ! has_teec "$OPTEE_CLIENT_EXPORT"; then
  ALT1="$REPO_ROOT/third_party/optee/build/optee_client/out/export/usr"
  if has_teec "$ALT1"; then
    echo "[tc] Using optee_client export at: $ALT1"
    OPTEE_CLIENT_EXPORT="$ALT1"
  fi
fi

# If not found, optionally build optee_client export automatically
if ! has_teec "$OPTEE_CLIENT_EXPORT"; then
  echo "[tc] optee_client export not found; bootstrapping via scripts/setup_optee_env.sh --client-only ..."
  bash "$REPO_ROOT/scripts/setup_optee_env.sh" --client-only --force --no-patch-tc || true
  # Re-evaluate candidates after setup
  if has_teec "$BR_SYSROOT_USR"; then
    OPTEE_CLIENT_EXPORT="$BR_SYSROOT_USR"
  elif has_teec "$REPO_ROOT/third_party/optee/optee_client/out/export/usr"; then
    OPTEE_CLIENT_EXPORT="$REPO_ROOT/third_party/optee/optee_client/out/export/usr"
  elif has_teec "$REPO_ROOT/third_party/optee/build/optee_client/out/export/usr"; then
    OPTEE_CLIENT_EXPORT="$REPO_ROOT/third_party/optee/build/optee_client/out/export/usr"
  else
    echo "[tc][warn] optee_client export still missing after setup. CMake will try system paths (libteec-dev)." >&2
    OPTEE_CLIENT_EXPORT=""
  fi
fi

OPENSSL_ARGS=()
if [[ -d "$BR_SYSROOT_USR/include/openssl" ]]; then
  if [[ -f "$BR_SYSROOT_USR/lib/libssl.so" || -f "$BR_SYSROOT_USR/lib/libssl.a" ]] && \
     [[ -f "$BR_SYSROOT_USR/lib/libcrypto.so" || -f "$BR_SYSROOT_USR/lib/libcrypto.a" ]]; then
    echo "[tc] Using cross OpenSSL from Buildroot sysroot: $BR_SYSROOT_USR"
    OPENSSL_ARGS=(
      -DOPENSSL_ROOT_DIR="$BR_SYSROOT_USR"
      -DOPENSSL_INCLUDE_DIR="$BR_SYSROOT_USR/include"
    )
    # Help CMake/pkg-config find libs in the sysroot
    export PKG_CONFIG_LIBDIR="$BR_SYSROOT_USR/lib/pkgconfig:${PKG_CONFIG_LIBDIR:-}"
    export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
  fi
fi

cd "$REPO_ROOT"
rm -rf build-aarch64 && mkdir build-aarch64
cd build-aarch64

# Hard-set cross compilers to avoid host fallback
export CC=aarch64-linux-gnu-gcc
export CXX=aarch64-linux-gnu-g++

CM_ARGS=(
  -DTEE_PLATFORM=optee
  -DCMAKE_SYSTEM_NAME=Linux
  -DCMAKE_SYSTEM_PROCESSOR=aarch64
  -DCMAKE_C_COMPILER="$CC"
  -DCMAKE_CXX_COMPILER="$CXX"
  -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/scripts/aarch64-toolchain.cmake"
)
if has_teec "$OPTEE_CLIENT_EXPORT"; then
  CM_ARGS+=( -DOPTEE_CLIENT_EXPORT="$OPTEE_CLIENT_EXPORT" )
else
  echo "[tc] Proceeding without OPTEE_CLIENT_EXPORT; expecting system cross libteec."
fi
CM_ARGS+=( "${OPENSSL_ARGS[@]}" )

cmake "${CM_ARGS[@]}" ..
cmake --build . -j"$(nproc)"

# Verify architecture of at least one produced binary
ARTIFACT="bin/test_cbor"
if [[ -f "$ARTIFACT" ]]; then
  FILE_OUT="$(file -b "$ARTIFACT" 2>/dev/null || true)"
  echo "[tc] file $ARTIFACT => $FILE_OUT"
  if ! echo "$FILE_OUT" | grep -qi 'aarch64'; then
    echo "[tc][ERROR] Unexpected target architecture for $ARTIFACT (expect AArch64)." >&2
    echo "           Please ensure aarch64-linux-gnu toolchain is installed and on PATH." >&2
    exit 2
  fi
fi

echo "[tc] built for aarch64 → ${PWD}/bin"

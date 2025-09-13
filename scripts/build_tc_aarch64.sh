#!/usr/bin/env bash
set -euo pipefail

# Load env and resolve paths
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/env-optee-qemu.sh"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OPTEE_CLIENT_EXPORT="${OPTEE_CLIENT_EXPORT:-$REPO_ROOT/third_party/optee/optee_client/out/export/usr}"

# Try to locate Buildroot aarch64 sysroot for OpenSSL
BR_SYSROOT_USR="$REPO_ROOT/third_party/optee/out-br/host/aarch64-buildroot-linux-gnu/sysroot/usr"
# Prefer TEEC from the target sysroot if available (avoid host x86_64 libteec)
if [[ -z "${FORCE_HOST_TEEC:-}" ]] && [[ -f "$BR_SYSROOT_USR/include/tee_client_api.h" ]] && \
   ([[ -f "$BR_SYSROOT_USR/lib/libteec.so" ]] || [[ -f "$BR_SYSROOT_USR/lib/libteec.a" ]]); then
  echo "[tc] Using TEE Client from Buildroot sysroot: $BR_SYSROOT_USR"
  OPTEE_CLIENT_EXPORT="$BR_SYSROOT_USR"
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

cmake -DTEE_PLATFORM=optee \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
      -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/scripts/aarch64-toolchain.cmake" \
      -DOPTEE_CLIENT_EXPORT="$OPTEE_CLIENT_EXPORT" \
      ${OPENSSL_ARGS[@]} ..

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

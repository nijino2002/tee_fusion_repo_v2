#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env-optee-qemu.sh"
cd "${BASEDIR}"

rm -rf build-aarch64 && mkdir build-aarch64
cd build-aarch64
cmake -DTEE_PLATFORM=optee -DCMAKE_TOOLCHAIN_FILE="${BASEDIR}/scripts/aarch64-toolchain.cmake" ..
make -j"$(nproc)"
echo "[tc] built for aarch64 → ${PWD}/bin"

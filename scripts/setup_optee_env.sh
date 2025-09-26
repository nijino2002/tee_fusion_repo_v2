#!/usr/bin/env bash
# setup_optee_env.sh — One-shot setup for OP-TEE (qemu-v8) essentials
# - Builds optee_os TA DevKit (export-ta_arm64)
# - Builds optee_client (exports headers + libteec)
# - Writes scripts/env-optee-qemu.sh with correct paths
# - (Optionally) patches scripts/build_tc_aarch64.sh to pass OPTEE_CLIENT_EXPORT
#
# Usage:
#   bash scripts/setup_optee_env.sh [--platform vexpress-qemu_armv8a|qemu_virt] [--force] [--no-patch-tc]
# Defaults:
#   platform auto-detect (prefer qemu_virt if present; else vexpress-qemu_armv8a)
#   --force   : cleans and rebuilds optee_os & optee_client outputs
#   --no-patch-tc : do not patch scripts/build_tc_aarch64.sh
#
set -euo pipefail

say()  { printf "\033[1;36m[setup]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*"; }
die()  { err "$*"; exit 1; }

# --- Paths ---
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTEE_ROOT="${BASEDIR}/third_party/optee"
OS_DIR="${OPTEE_ROOT}/optee_os"
CLIENT_DIR="${OPTEE_ROOT}/optee_client"
BUILD_DIR="${OPTEE_ROOT}/build"
ENV_FILE="${BASEDIR}/scripts/env-optee-qemu.sh"

# --- Args ---
PLATFORM="auto"
FORCE=0
PATCH_TC=1
CLIENT_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2;;
    --force)    FORCE=1; shift;;
    --no-patch-tc) PATCH_TC=0; shift;;
    --client-only) CLIENT_ONLY=1; shift;;
    -h|--help)
      cat <<'USAGE'
Usage: bash scripts/setup_optee_env.sh [options]
  --platform <name>   vexpress-qemu_armv8a | qemu_virt (default: auto-detect)
  --force             clean & rebuild optee_os and optee_client
  --no-patch-tc       do not patch scripts/build_tc_aarch64.sh
USAGE
      exit 0;;
    *) die "Unknown option: $1";;
  esac
done

say "Base dir: ${BASEDIR}"
[[ -d "${CLIENT_DIR}" ]] || die "Missing ${CLIENT_DIR}. Did you 'repo init/sync' manifest into third_party/optee?"
if [[ ${CLIENT_ONLY} -eq 0 ]]; then
  [[ -d "${OS_DIR}" ]] || die "Missing ${OS_DIR}. Did you 'repo init/sync' manifest into third_party/optee?"
fi

# --- Determine toolchains ---
CROSS64=""
if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  CROSS64="aarch64-linux-gnu-"
elif [[ -x "${OPTEE_ROOT}/toolchains/aarch64/bin/aarch64-linux-gnu-gcc" ]]; then
  export PATH="${OPTEE_ROOT}/toolchains/aarch64/bin:${PATH}"
  CROSS64="aarch64-linux-gnu-"
fi
[[ -n "${CROSS64}" ]] || die "aarch64 toolchain not found. Run 'make deps' or ensure ${OPTEE_ROOT}/toolchains is present."

say "Using CROSS_COMPILE64=${CROSS64}"

if [[ ${CLIENT_ONLY} -eq 0 ]]; then
  # --- Determine PLATFORM ---
  if [[ "${PLATFORM}" == "auto" ]]; then
    if [[ -d "${OS_DIR}/core/arch/arm/plat-qemu_virt" ]]; then
      PLATFORM="qemu_virt"
    else
      PLATFORM="vexpress-qemu_armv8a"
    fi
  fi
  say "Using PLATFORM=${PLATFORM} (you can override with --platform ...)"
fi

if [[ ${CLIENT_ONLY} -eq 0 ]]; then
  # --- Build optee_os (TA DevKit) ---
  pushd "${OS_DIR}" >/dev/null
    if [[ ${FORCE} -eq 1 ]]; then
      say "Cleaning ${OS_DIR}/out/arm ..."
      rm -rf out/arm
    fi
    say "Building optee_os (this may take a few minutes)..."
    make -j"$(nproc)" \
      CROSS_COMPILE64="${CROSS64}" \
      PLATFORM="${PLATFORM}" \
      CFG_ARM64_core=y \
      CFG_TA_ARM32_SUPPORT=n \
      O=out/arm || true

    EXPORT_DIR="out/arm/export-ta_arm64"
    [[ -d "${EXPORT_DIR}" ]] || die "TA DevKit not found at ${OS_DIR}/${EXPORT_DIR}"
    EXPORT_ABS="${OS_DIR}/${EXPORT_DIR}"
    ok "TA DevKit: ${EXPORT_ABS}"
  popd >/dev/null
else
  EXPORT_ABS="${TA_DEV_KIT_DIR}"
fi

# --- Build & export optee_client ---
pushd "${CLIENT_DIR}" >/dev/null
  if [[ ${FORCE} -eq 1 ]]; then
    say "Cleaning ${CLIENT_DIR}/build and ${CLIENT_DIR}/out/export ..."
    rm -rf build out/export
  fi
  say "Configuring optee_client with CMAKE_INSTALL_PREFIX=out/export/usr ..."
  cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${CLIENT_DIR}/out/export/usr"
  say "Building optee_client ..."
  cmake --build build -j"$(nproc)"
  say "Installing optee_client to ${CLIENT_DIR}/out/export/usr ..."
  cmake --install build

  CLIENT_EXPORT="${CLIENT_DIR}/out/export/usr"
  [[ -f "${CLIENT_EXPORT}/include/tee_client_api.h" ]] || die "Missing ${CLIENT_EXPORT}/include/tee_client_api.h"
  if [[ ! -f "${CLIENT_EXPORT}/lib/libteec.so" && ! -f "${CLIENT_EXPORT}/lib/libteec.a" ]]; then
    die "optee_client export seems incomplete at ${CLIENT_EXPORT}"
  fi
  ok "optee_client export: ${CLIENT_EXPORT}"
popd >/dev/null

# --- Update env file ---
say "Writing ${ENV_FILE} ..."
mkdir -p "$(dirname "${ENV_FILE}")"
cat > "${ENV_FILE}" <<EOF
#!/usr/bin/env bash
export BASEDIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
export OPTEE_BUILD_DIR="\${BASEDIR}/third_party/optee/build"
export OPTEE_OS_EXPORT="${EXPORT_ABS}"
export TA_DEV_KIT_DIR="${EXPORT_ABS}"
export CROSS_COMPILE=aarch64-linux-gnu-
export QEMU_SSH_PORT=10022
export QEMU_GUEST_USER=root
export QEMU_GUEST_PASS=root
EOF
chmod +x "${ENV_FILE}"
ok "env updated: ${ENV_FILE}"

# --- Optionally patch build_tc_aarch64.sh to pass OPTEE_CLIENT_EXPORT ---
if [[ ${PATCH_TC} -eq 1 ]]; then
  TC_SH="${BASEDIR}/scripts/build_tc_aarch64.sh"
  if [[ -f "${TC_SH}" ]]; then
    if ! grep -q "OPTEE_CLIENT_EXPORT" "${TC_SH}"; then
      say "Patching ${TC_SH} to pass -DOPTEE_CLIENT_EXPORT=${CLIENT_EXPORT} ..."
      cp -f "${TC_SH}" "${TC_SH}.bak"
      awk -v export_path="${CLIENT_EXPORT}" '
        /cmake[[:space:]]+-DTEE_PLATFORM=optee/ && !patched {
          sub(/\.\./, "-DOPTEE_CLIENT_EXPORT=\"" export_path "\" ..");
          patched=1;
        }
        { print }
      ' "${TC_SH}.bak" > "${TC_SH}.new" || { err "Failed to patch ${TC_SH}"; mv -f "${TC_SH}.bak" "${TC_SH}"; exit 1; }
      mv -f "${TC_SH}.new" "${TC_SH}"
      chmod +x "${TC_SH}"
      ok "Patched ${TC_SH} (backup at ${TC_SH}.bak)"
    else
      ok "${TC_SH} already passes OPTEE_CLIENT_EXPORT"
    fi
  else
    warn "Not found: ${TC_SH}; skip patch."
  fi
else
  warn "--no-patch-tc specified; remember to pass -DOPTEE_CLIENT_EXPORT=${CLIENT_EXPORT} to CMake manually."
fi

# --- Final summary ---
cat <<SUM

\033[1;34m=== Setup complete ===\033[0m
TA DevKit:   ${EXPORT_ABS}
optee_client export:
  include -> ${CLIENT_EXPORT}/include
  libs    -> ${CLIENT_EXPORT}/lib

Next steps:
  1) Build TA
     \033[1mmake ta\033[0m

  2) Build TC (aarch64)  — if patched:
     \033[1mmake tc-aarch64\033[0m

     Or configure manually:
     \033[1mmkdir -p build && cd build
cmake -DTEE_PLATFORM=optee -DOPTEE_CLIENT_EXPORT="${CLIENT_EXPORT}" ..
make -j"$(nproc)"\033[0m

  3) (Optional) Start QEMU + deploy + selftest
     \033[1mmake qemu
make deploy
make selftest\033[0m

If anything fails, re-run with \033[1m--force\033[0m to clean outputs, and share the first error lines.

SUM

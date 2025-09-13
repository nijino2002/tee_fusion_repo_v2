#!/usr/bin/env bash
# Robust TA build script (no BASEDIR collision)

set -euo pipefail

# Resolve repo root from THIS script, and keep it immutable
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[ta] REPO_ROOT=${REPO_ROOT}"

# Source OP-TEE env (but DO NOT trust its BASEDIR)
ENV_FILE="${REPO_ROOT}/scripts/env-optee-qemu.sh"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
else
  echo "[ta] ERROR: ${ENV_FILE} not found. Run scripts/setup_optee_env.sh first." >&2
  exit 1
fi

# Prefer variables from env for toolchain/devkit, but always use REPO_ROOT for paths in this repo
: "${TA_DEV_KIT_DIR:?TA_DEV_KIT_DIR missing. Check ${ENV_FILE}}"
if [[ ! -d "${TA_DEV_KIT_DIR}" ]]; then
  echo "[ta] ERROR: TA_DEV_KIT_DIR does not exist: ${TA_DEV_KIT_DIR}" >&2
  exit 1
fi

TADIR="${REPO_ROOT}/optee/ta"
if [[ ! -d "${TADIR}" ]]; then
  echo "[ta] ERROR: TA dir not found: ${TADIR}" >&2
  exit 1
fi

echo "[ta] Using TA_DEV_KIT_DIR=${TA_DEV_KIT_DIR}"
echo "[ta] Building in ${TADIR}"

# Clean + build
make -C "${TADIR}" clean || true
make -C "${TADIR}" -j"$(nproc)"

# Show artifact (best-effort)
UUID_HEX=$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "${TADIR}"/ta_uuid.h 2>/dev/null | head -n1 || true)
if [[ -n "${UUID_HEX}" ]]; then
  TA_FILE="${TADIR}/${UUID_HEX}.ta"
  if [[ -f "${TA_FILE}" ]]; then
    echo "[ta] Built TA: ${TA_FILE}"
  else
    echo "[ta] Build finished. TA expected near ${TADIR}/ (check make output)."
  fi
else
  echo "[ta] Build finished."
fi

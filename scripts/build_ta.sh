#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env-optee-qemu.sh"
cd "${BASEDIR}"

if [ ! -d "${TA_DEV_KIT_DIR}" ]; then
  echo "TA_DEV_KIT_DIR not found, please run scripts/setup_optee_qemu_v8.sh" >&2
  exit 1
fi

make -C optee/ta
echo "[ta] built"
TA_UUID_HEX="7a9b3b24-3e2f-4d5f-912d-8b7c1355629a"
TA_BIN="optee/ta/${TA_UUID_HEX}.ta"
[ -f "${TA_BIN}" ] && echo "[ta] artifact: ${TA_BIN}"

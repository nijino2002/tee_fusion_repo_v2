#!/usr/bin/env bash
set -euo pipefail

# Load environment and resolve repo root
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/env-optee-qemu.sh"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT"

TA_UUID_HEX="7a9b3b24-3e2f-4d5f-912d-8b7c1355629a"
TA_BIN="optee/ta/${TA_UUID_HEX}.ta"
TC_BIN_DIR="${REPO_ROOT}/build-aarch64/bin"

if [ ! -f "${TA_BIN}" ]; then
  echo "missing TA: ${TA_BIN}. Run scripts/build_ta.sh" >&2
  exit 1
fi
if [ ! -d "${TC_BIN_DIR}" ]; then
  echo "missing TC bin dir: ${TC_BIN_DIR}. Run scripts/build_tc_aarch64.sh" >&2
  exit 1
fi

sshpass -p "${QEMU_GUEST_PASS}" scp -P ${QEMU_SSH_PORT} -o StrictHostKeyChecking=no \
  "${TA_BIN}" "${QEMU_GUEST_USER}@127.0.0.1:/lib/optee_armtz/"

sshpass -p "${QEMU_GUEST_PASS}" scp -P ${QEMU_SSH_PORT} -o StrictHostKeyChecking=no \
  "${TC_BIN_DIR}/selftest_crypto" \
  "${TC_BIN_DIR}/ratls_server" \
  "${TC_BIN_DIR}/ratls_client" \
  "${QEMU_GUEST_USER}@127.0.0.1:/root/"

echo "[push] done"

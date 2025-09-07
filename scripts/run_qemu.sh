#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env-optee-qemu.sh"

cd "${OPTEE_BUILD_DIR}"
make run-only &
QEMU_PID=$!

echo "[qemu] waiting for SSH on :${QEMU_SSH_PORT} ..."
for i in $(seq 1 60); do
  if nc -z localhost ${QEMU_SSH_PORT}; then
    echo "[qemu] ssh is ready"
    break
  fi
  sleep 2
done

echo "${QEMU_PID}" > "${OPTEE_BUILD_DIR}/.qemu_pid"
echo "[qemu] PID=${QEMU_PID}"
wait ${QEMU_PID} || true

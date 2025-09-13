#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (this script lives in scripts/)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Source env; tolerate missing/partial vars
ENV_FILE="${REPO_ROOT}/scripts/env-optee-qemu.sh"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "[run_qemu] WARN: ${ENV_FILE} not found; will fallback to defaults."
fi

# Fallbacks if env file didn't set them
OPTEE_BUILD_DIR="${OPTEE_BUILD_DIR:-${REPO_ROOT}/third_party/optee/build}"
QEMU_SSH_PORT="${QEMU_SSH_PORT:-2222}"

echo "[run_qemu] REPO_ROOT=${REPO_ROOT}"
echo "[run_qemu] OPTEE_BUILD_DIR=${OPTEE_BUILD_DIR}"
echo "[run_qemu] QEMU_SSH_PORT=${QEMU_SSH_PORT}"

# Ensure OP-TEE images and out/bin exist; prefer system QEMU if available
OPTEE_ROOT="$(cd "${OPTEE_BUILD_DIR}/.." && pwd)"
QEMU_A="${OPTEE_ROOT}/qemu/build/qemu-system-aarch64"
QEMU_B="${OPTEE_ROOT}/qemu/build/aarch64-softmmu/qemu-system-aarch64"
ROOTFS_GZ="${OPTEE_ROOT}/out-br/images/rootfs.cpio.gz"
OPTEE_BIN_DIR="${OPTEE_ROOT}/out/bin"
UIMAGE_BIN="${OPTEE_BIN_DIR}/uImage"
UROOTFS_BIN="${OPTEE_BIN_DIR}/rootfs.cpio.uboot"
SYS_QEMU_BIN="$(command -v qemu-system-aarch64 || true)"
OVERRIDE_QEMU_BIN=""

# Prefer system QEMU to avoid rebuilding locally
if [[ -x "${SYS_QEMU_BIN}" ]]; then
  echo "[run_qemu] Using system QEMU: ${SYS_QEMU_BIN}"
  OVERRIDE_QEMU_BIN="QEMU_BIN=${SYS_QEMU_BIN}"
else
  # Build QEMU locally if missing
  if [[ ! -x "${QEMU_A}" && ! -x "${QEMU_B}" ]]; then
    echo "[run_qemu] Local QEMU not found; building 'qemu' ..."
    make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" qemu
  fi
fi

# Build all images if key artifacts are missing
if [[ ! -f "${ROOTFS_GZ}" ]]; then
  echo "[run_qemu] Images missing; building 'all' (linux/optee-os/buildroot) ..."
  make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" all
fi

# Ensure the symlink target directory exists (run-only expects it)
mkdir -p "${OPTEE_BIN_DIR}"

# Ensure kernel Image symlink exists
if [[ ! -f "${OPTEE_BIN_DIR}/Image" ]]; then
  echo "[run_qemu] Kernel Image missing; building 'linux' ..."
  make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" linux
fi

# Ensure TF-A/OP-TEE binaries are linked if missing
if [[ ! -f "${OPTEE_BIN_DIR}/bl1.bin" ]]; then
  echo "[run_qemu] TF-A bl1.bin missing; building 'arm-tf' ..."
  make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" arm-tf
fi
if [[ ! -f "${OPTEE_BIN_DIR}/bl32.bin" ]]; then
  echo "[run_qemu] OP-TEE bl32.bin missing; building 'optee-os' ..."
  make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" optee-os
fi

# Ensure U-Boot expected images (uImage/uRootfs) exist
if [[ ! -f "${UIMAGE_BIN}" ]]; then
  echo "[run_qemu] U-Boot uImage missing; building 'uImage' ..."
  make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" uImage
fi
if [[ ! -f "${UROOTFS_BIN}" ]]; then
  echo "[run_qemu] U-Boot rootfs.cpio.uboot missing; building 'uRootfs' ..."
  make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" uRootfs
fi

# Ensure OP-TEE images and out/bin exist; rebuild if missing
OPTEE_ROOT="$(cd "${OPTEE_BUILD_DIR}/.." && pwd)"
if [[ ! -d "${OPTEE_ROOT}/out/bin" ]] || [[ ! -f "${OPTEE_ROOT}/out-br/images/rootfs.cpio.gz" ]]; then
  echo "[run_qemu] Preparing OP-TEE images via 'make qemu_v8' ..."
  make -C "${OPTEE_BUILD_DIR}" -j"$(nproc)" qemu_v8
fi

# Sanity checks
if [[ ! -d "${OPTEE_BUILD_DIR}" ]]; then
  echo "[run_qemu] ERROR: OPTEE_BUILD_DIR does not exist: ${OPTEE_BUILD_DIR}"
  echo "  - Ensure you have run: scripts/setup_optee_env.sh --platform vexpress-qemu_armv8a"
  echo "  - Or verify your env file sets OPTEE_BUILD_DIR correctly."
  exit 1
fi

cd "${OPTEE_BUILD_DIR}"

# Resolve optional system QEMU fallback
SYS_QEMU_BIN="$(command -v qemu-system-aarch64 || true)"
OVERRIDE_QEMU_BIN=""
if [[ ! -x "${QEMU_A}" && ! -x "${QEMU_B}" && -x "${SYS_QEMU_BIN}" ]]; then
  echo "[run_qemu] Using system QEMU: ${SYS_QEMU_BIN}"
  OVERRIDE_QEMU_BIN="QEMU_BIN=${SYS_QEMU_BIN}"
fi

# Prefer 'run-only' if available, otherwise fallback to 'run'
RUN_TARGET="run-only"
if ! make ${OVERRIDE_QEMU_BIN} -n "${RUN_TARGET}" >/dev/null 2>&1; then
  if make ${OVERRIDE_QEMU_BIN} -n run >/dev/null 2>&1; then
    RUN_TARGET="run"
  else
    echo "[run_qemu] ERROR: Neither 'run-only' nor 'run' target exists in ${OPTEE_BUILD_DIR}"
    echo "  Try: make help   (to list available targets)"
    exit 1
  fi
fi

echo "[run_qemu] Starting QEMU via 'make ${RUN_TARGET}' ..."
make ${OVERRIDE_QEMU_BIN} "${RUN_TARGET}" &
QEMU_PID=$!
echo "[run_qemu] QEMU PID=${QEMU_PID}"

# Wait for SSH readiness (up to ~120s)
echo "[run_qemu] waiting for SSH on :${QEMU_SSH_PORT} ..."
READY=0

if command -v nc >/dev/null 2>&1; then
  for _ in $(seq 1 60); do
    if nc -z localhost "${QEMU_SSH_PORT}" 2>/dev/null; then
      READY=1; break
    fi
    sleep 2
  done
else
  echo "[run_qemu] 'nc' not found, using /dev/tcp fallback"
  for _ in $(seq 1 60); do
    if (echo >/dev/tcp/127.0.0.1/"${QEMU_SSH_PORT}") >/dev/null 2>&1; then
      READY=1; break
    fi
    sleep 2
  done
fi

if [[ "${READY}" -eq 1 ]]; then
  echo "[qemu] ssh is ready"
else
  echo "[run_qemu] WARN: SSH not ready after timeout; QEMU may still be booting."
  echo "  You can re-run this script, or check QEMU console output for progress."
fi

echo "${QEMU_PID}" > "${OPTEE_BUILD_DIR}/.qemu_pid" || true
# Keep parent make from failing if QEMU exits with non-zero on ctrl-c etc.
wait "${QEMU_PID}" || true

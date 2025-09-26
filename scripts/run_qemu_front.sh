#!/usr/bin/env bash
set -euo pipefail

# Interactive QEMU launcher with resilient GDB port handling.
# - Mirrors OP-TEE build's `run-only` invocation but avoids failure when
#   default GDB stub port 1234 is busy by switching to a free port.
# - Preserves waiting for 'c' (keeps '-S') so the user can continue normal world.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/scripts/env-optee-qemu.sh"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi
OPTEE_BUILD_DIR="${OPTEE_BUILD_DIR:-${REPO_ROOT}/third_party/optee/build}"

# Probe the QEMU command that run-only would execute (without executing it)
set +e
SSH_PORT="${QEMU_SSH_PORT:-10022}"
RAW=$(
  HOSTFWD=",hostfwd=tcp::${SSH_PORT}-:22" \
  QEMU_EXTRA_ARGS="${QEMU_EXTRA_ARGS:-}" \
  make -C "${OPTEE_BUILD_DIR}" -n run-only 2>/dev/null | \
  grep -E "qemu-system-(aarch64|arm)" | \
  tail -n 1
)
set -e
if [[ -z "${RAW}" ]]; then
  echo "[run_qemu_front] Could not derive QEMU command. Falling back to make run-only ..."
  exec env HOSTFWD=",hostfwd=tcp::${SSH_PORT}-:22" \
       QEMU_EXTRA_ARGS="${QEMU_EXTRA_ARGS:-}" \
       make -C "${OPTEE_BUILD_DIR}" run-only
fi

# Extract working dir and command (robust without bash regex)
WORKDIR="${OPTEE_BUILD_DIR}"
CMDLINE="${RAW}"
PARSED=$(printf '%s\n' "${RAW}" | awk 'match($0, /^cd[ \t]+([^&]+)[ \t]+&&[ \t]+(.*)$/, a){print a[1] "\n" a[2]; found=1} END{ if(!found) print "" }')
if [[ -n "${PARSED}" ]]; then
  WORKDIR="$(printf '%s' "${PARSED}" | sed -n '1p')"
  CMDLINE="$(printf '%s' "${PARSED}" | sed -n '2p')"
fi

# Choose a free GDB port (prefer 1234; else try 1235..1249)
choose_port() {
  local p
  for ((p=1234; p<=1249; p++)); do
    if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${p}$"; then
      echo "$p"; return 0
    fi
  done
  echo 0
}
GDB_PORT=$(choose_port)

# Rewrite '-s -S' into '-S -gdb tcp::PORT' if needed
if [[ "${GDB_PORT}" != "1234" ]]; then
  CMDLINE_MODIFIED="${CMDLINE// -s -S / -S -gdb tcp::${GDB_PORT} }"
else
  CMDLINE_MODIFIED="${CMDLINE}"
fi

echo "[run_qemu_front] workdir: ${WORKDIR}"
echo "[run_qemu_front] gdb port: ${GDB_PORT}"
echo "[run_qemu_front] qemu cmd: ${CMDLINE_MODIFIED}"

# Extract serial ports from the command line and spawn terminals
readarray -t SERIAL_PORTS < <(printf '%s\n' "${CMDLINE_MODIFIED}" | \
  grep -oE 'serial tcp:127\.0\.0\.1:[0-9]+' | awk -F: '{print $NF}')

launch_soc_term() {
  local port="$1"; local title="$2";
  # If already listening, skip
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    echo "[run_qemu_front] port $port already in use; skip spawning $title terminal"
    return 0
  fi
  local SOC_TERM="${OPTEE_BUILD_DIR}/../build/soc_term.py"
  if [[ ! -f "${SOC_TERM}" ]]; then
    SOC_TERM="${OPTEE_BUILD_DIR}/soc_term.py"
  fi
  if command -v tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
    tmux split-window -d -h "${SOC_TERM} ${port}" || tmux new-window -d -n "OPTEE_$$" "${SOC_TERM} ${port}"
  elif command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --title="${title}" -- bash -lc "'${SOC_TERM}' ${port}" &
  elif command -v xterm >/dev/null 2>&1; then
    xterm -title "${title}" -e bash -lc "'${SOC_TERM}' ${port}" &
  else
    # Fallback: background process (may interfere with current TTY)
    "${SOC_TERM}" "${port}" &
  fi
}

if [[ ${#SERIAL_PORTS[@]} -ge 1 ]]; then
  launch_soc_term "${SERIAL_PORTS[0]}" "Normal World"
fi
if [[ ${#SERIAL_PORTS[@]} -ge 2 ]]; then
  launch_soc_term "${SERIAL_PORTS[1]}" "Secure World"
fi

# Wait for ports to be ready (max ~20s)
for p in "${SERIAL_PORTS[@]}"; do
  for _ in $(seq 1 40); do
    if nc -z 127.0.0.1 "$p" 2>/dev/null; then break; fi; sleep 0.5
  done
done

cd "${WORKDIR}"
exec bash -lc "${CMDLINE_MODIFIED}"

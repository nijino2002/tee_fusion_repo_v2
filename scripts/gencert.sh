#!/usr/bin/env bash
set -euo pipefail

# Generate a self-signed TLS key/cert pair for ratls_server demo.
# Outputs: server.key (PEM), server.crt (PEM) in repo root.
# Usage: bash scripts/gencert.sh [--cn <common_name>] [--days <n>] [--out <prefix>]

CN="tee-fusion RATLS"
DAYS=365
OUT_PREFIX="server"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) CN="${2:-}"; shift 2;;
    --days) DAYS="${2:-}"; shift 2;;
    --out) OUT_PREFIX="${2:-}"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--cn <common_name>] [--days <n>] [--out <prefix>]"; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

KEY="${OUT_PREFIX}.key"
CRT="${OUT_PREFIX}.crt"

echo "[gencert] Generating ECDSA P-256 key and self-signed cert ..."
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -sha256 \
  -days "${DAYS}" -nodes -keyout "${KEY}" -out "${CRT}" \
  -subj "/CN=${CN}/O=tee_fusion" >/dev/null 2>&1 || {
  echo "[gencert] OpenSSL failed (is openssl installed?)" >&2; exit 1;
}

echo "[gencert] Wrote: $(pwd)/${KEY}"
echo "[gencert] Wrote: $(pwd)/${CRT}"
echo "[gencert] Done."


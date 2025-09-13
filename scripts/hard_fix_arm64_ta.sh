#!/usr/bin/env bash
set -euo pipefail

# --- resolve repo root ---
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
echo "[fix] REPO_ROOT=$REPO_ROOT"

# --- source env if present (但不让其覆盖本脚本解析的 REPO_ROOT) ---
ENV_FILE="$REPO_ROOT/scripts/env-optee-qemu.sh"
if [[ -f "$ENV_FILE" ]]; then
  # 先保留当前 REPO_ROOT，再 source，然后若对方未设置有效路径则回退
  __LOCAL_REPO_ROOT__="$REPO_ROOT"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [[ -z "${REPO_ROOT:-}" || ! -d "$REPO_ROOT" ]]; then
    REPO_ROOT="$__LOCAL_REPO_ROOT__"
  fi
fi

# --- toolchain sanity ---
if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  echo "[fix][ERROR] aarch64-linux-gnu-gcc 未安装。Ubuntu安装："
  echo "  sudo apt-get update && sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
  exit 1
fi

# --- extract UUID from adapters/optee/optee_fusion_ta_uuid.h ---
UUID_HDR="$REPO_ROOT/adapters/optee/optee_fusion_ta_uuid.h"
if [[ ! -f "$UUID_HDR" ]]; then
  echo "[fix][ERROR] 缺少 $UUID_HDR"
  exit 1
fi
# 把 { 0x7a9b3b24, 0x3e2f, 0x4d5f, { 0x91, 0x2d, 0x8b, 0x7c, 0x13, 0x55, 0x62, 0x9a } }
# 转成 7a9b3b24-3e2f-4d5f-912d-8b7c1355629a
UUID_STR="$(
  awk '
    /TA_OPTEE_FUSION_UUID/ {
      gsub(/[^0-9a-fA-Fx,]/,"")
      split($0,a,",")
      # a[1]={0x7a9b3b24  -> take hex after 0x
      sub(/.*0x/,"",a[1]); gsub(/[^0-9a-fA-F]/,"",a[1])
      sub(/.*0x/,"",a[2]); gsub(/[^0-9a-fA-F]/,"",a[2])
      sub(/.*0x/,"",a[3]); gsub(/[^0-9a-fA-F]/,"",a[3])
      # following 8 bytes for node
      n[1]=a[4]; n[2]=a[5]; n[3]=a[6]; n[4]=a[7]; n[5]=a[8]; n[6]=a[9]; n[7]=a[10]; n[8]=a[11]
      for(i=1;i<=8;i++){ sub(/.*0x/,"",n[i]); gsub(/[^0-9a-fA-F]/,"",n[i]); if(length(n[i])==1) n[i]="0" n[i] }
      # time_hi_and_version is a[3]; next 2 bytes combine to last 12 hex
      # clock_seq_hi,clock_seq_low = n1,n2 ; node = n3..n8
      printf "%s-%s-%s-%s%s-%s%s%s%s%s%s\n",
        a[1], a[2], a[3], n[1], n[2], n[3], n[4], n[5], n[6], n[7], n[8]
      exit
    }
  ' "$UUID_HDR"
)"
if [[ -z "$UUID_STR" ]]; then
  echo "[fix][ERROR] 无法从 $UUID_HDR 解析 UUID"
  exit 1
fi
echo "[fix] TA UUID = $UUID_STR"

# --- ensure TA DevKit (arm64-only); if missing, build it ---
OS_DIR="$REPO_ROOT/third_party/optee/optee_os"
TA_DEV_KIT_DIR_DEFAULT="$OS_DIR/out/arm/export-ta_arm64"
TA_DEV_KIT_DIR="${TA_DEV_KIT_DIR:-$TA_DEV_KIT_DIR_DEFAULT}"

if [[ ! -d "$TA_DEV_KIT_DIR" ]]; then
  echo "[fix] TA DevKit 不存在，开始构建 optee_os (arm64-only) ..."
  rm -rf "$OS_DIR/out"
  # 强制 arm64-only：关键在 CFG_USER_TA_TARGETS=ta_arm64；并禁用 ARM32 core/TA
  make -C "$OS_DIR" -j"$(nproc)" \
    CROSS_COMPILE64=aarch64-linux-gnu- \
    PLATFORM=vexpress-qemu_armv8a \
    CFG_ARM64_core=y CFG_ARM32_core=n \
    CFG_USER_TA_TARGETS=ta_arm64 CFG_TA_ARM64=y CFG_TA_ARM32=n \
    O=out/arm
  if [[ ! -d "$TA_DEV_KIT_DIR_DEFAULT" ]]; then
    echo "[fix][ERROR] 构建完成后仍找不到 TA DevKit: $TA_DEV_KIT_DIR_DEFAULT"
    exit 1
  fi
  TA_DEV_KIT_DIR="$TA_DEV_KIT_DIR_DEFAULT"
fi
echo "[fix] TA_DEV_KIT_DIR = $TA_DEV_KIT_DIR"

# --- write env-optee-qemu.sh for future shells ---
cat > "$ENV_FILE" <<EOF
#!/usr/bin/env bash
export REPO_ROOT="$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
export TA_DEV_KIT_DIR="$TA_DEV_KIT_DIR"
export OPTEE_CLIENT_EXPORT="\$REPO_ROOT/third_party/optee/optee_client/out/export/usr"
export TEEC_INCLUDE_DIR="\$OPTEE_CLIENT_EXPORT/include"
export TEEC_LIB="\$OPTEE_CLIENT_EXPORT/lib/libteec.a"
export OPTEE_BUILD_DIR="\$REPO_ROOT/third_party/optee/build"
export QEMU_SSH_PORT="\${QEMU_SSH_PORT:-2222}"
export CROSS_COMPILE=aarch64-linux-gnu-
EOF
chmod +x "$ENV_FILE"
echo "[fix] 已写入 $ENV_FILE"

# --- patch optee/ta/Makefile (force arm64-only + CROSS_COMPILE + BINARY) ---
TA_MK="$REPO_ROOT/optee/ta/Makefile"
if [[ ! -f "$TA_MK" ]]; then
  echo "[fix][ERROR] 缺少 $TA_MK"
  exit 1
fi

# 生成新内容（包含 BINARY、强制 TA_TARGETS、CROSS_COMPILE）
cat > "$TA_MK" <<EOF
BINARY := $UUID_STR

TA_TARGETS       ?= ta_arm64
CFG_TA_ARM64     ?= y
CFG_TA_ARM32     ?= n
CROSS_COMPILE    ?= aarch64-linux-gnu-

include \$(TA_DEV_KIT_DIR)/mk/ta_dev_kit.mk
EOF
echo "[fix] 已覆盖 $TA_MK（arm64-only & CROSS_COMPILE 已固化）"

# --- ensure sub.mk include paths ---
SUBMK="$REPO_ROOT/optee/ta/sub.mk"
add_line() {
  local L="$1"
  grep -qF -- "$L" "$SUBMK" || echo "$L" >> "$SUBMK"
}
if [[ -f "$SUBMK" ]]; then
  add_line 'global-incdirs-y += .'
  add_line 'global-incdirs-y += ../../include'
  add_line 'global-incdirs-y += ../../adapters/optee'
  echo "[fix] 已确保头文件检索路径在 optee/ta/sub.mk"
else
  echo "[fix][ERROR] 缺少 $SUBMK"
  exit 1
fi

# --- export CROSS_COMPILE in this shell and build TA ---
export CROSS_COMPILE=aarch64-linux-gnu-
echo "[fix] 开始编译 TA ..."
make -C "$REPO_ROOT/optee/ta" clean
make -C "$REPO_ROOT/optee/ta" V=1

echo "[fix] OK. 产物应位于：optee/ta/$UUID_STR.ta"

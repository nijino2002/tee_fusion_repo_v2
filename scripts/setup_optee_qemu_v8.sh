#!/usr/bin/env bash
set -euo pipefail

# ===== Configurable =====
OPTEE_MANIFEST_URL="${OPTEE_MANIFEST_URL:-https://github.com/OP-TEE/manifest.git}"
OPTEE_MANIFEST_BRANCH="${OPTEE_MANIFEST_BRANCH:-master}"   # 可改成 stable 分支或某 tag
OPTEE_MANIFEST_FILE="${OPTEE_MANIFEST_FILE:-qemu_v8.xml}"  # 也可用 default.xml

# ===== Paths =====
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPTEE_ROOT="${REPO_ROOT}/third_party/optee"       # manifest 根目录
BUILD_DIR="${OPTEE_ROOT}/build"                   # repo 同步后会有 build/ 子仓库
EXPORT_TA64="${OPTEE_ROOT}/optee_os/out/arm/export-ta_arm64"  # 仅导出 arm64 TA DevKit

# 确保依赖（包含 repo）
"${REPO_ROOT}/scripts/install_deps_ubuntu.sh"

mkdir -p "${OPTEE_ROOT}"
cd "${OPTEE_ROOT}"

# 初始化/更新 manifest
if [ ! -d .repo ]; then
  echo "[optee] repo init -u ${OPTEE_MANIFEST_URL} -b ${OPTEE_MANIFEST_BRANCH} -m ${OPTEE_MANIFEST_FILE}"
  repo init -u "${OPTEE_MANIFEST_URL}" -b "${OPTEE_MANIFEST_BRANCH}" -m "${OPTEE_MANIFEST_FILE}"
fi

echo "[optee] repo sync (this may take a while)"
repo sync -j"$(nproc)" --force-sync

# 编译工具链与 qemu_v8
echo "[optee] make toolchains && make qemu_v8"
make -C "${BUILD_DIR}" -j"$(nproc)" toolchains
make -C "${BUILD_DIR}" -j"$(nproc)" qemu_v8

# 确保仅生成 arm64 的 TA DevKit
echo "[optee] build arm64 TA devkit"
unset CROSS_COMPILE || true
make -C "${OPTEE_ROOT}/optee_os" -j"$(nproc)" \
  PLATFORM=vexpress-qemu_armv8a \
  CFG_ARM64_core=y CFG_ARM32_core=n \
  CFG_USER_TA_TARGETS=ta_arm64 \
  CROSS_COMPILE64=aarch64-linux-gnu- \
  O=out/arm ta_dev_kit

# 校验导出目录
if [ ! -d "${EXPORT_TA64}" ]; then
  echo "[optee][ERROR] TA devkit not found at ${EXPORT_TA64}" >&2
  exit 1
fi

# 为工程的其它脚本导出统一变量（动态解析 REPO_ROOT）
cat > "${REPO_ROOT}/scripts/env-optee-qemu.sh" <<'EOF'
#!/usr/bin/env bash
# 统一环境：仅 arm64 TA DevKit
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPTEE_ROOT="$REPO_ROOT/third_party/optee"
export OPTEE_BUILD_DIR="$OPTEE_ROOT/build"
export TA_DEV_KIT_DIR="$OPTEE_ROOT/optee_os/out/arm/export-ta_arm64"
export OPTEE_OS_EXPORT="$TA_DEV_KIT_DIR"
export OPTEE_CLIENT_EXPORT="$REPO_ROOT/third_party/optee/optee_client/out/export/usr"
export TEEC_INCLUDE_DIR="$OPTEE_CLIENT_EXPORT/include"
export TEEC_LIB="$OPTEE_CLIENT_EXPORT/lib/libteec.a"
export QEMU_SSH_PORT="${QEMU_SSH_PORT:-2222}"
export QEMU_GUEST_USER="${QEMU_GUEST_USER:-root}"
export QEMU_GUEST_PASS="${QEMU_GUEST_PASS:-root}"
export CROSS_COMPILE=aarch64-linux-gnu-
EOF
chmod +x "${REPO_ROOT}/scripts/env-optee-qemu.sh"

echo "[optee] setup done. TA_DEV_KIT_DIR=${EXPORT_TA64}"

#!/usr/bin/env bash
set -euo pipefail

# ===== Configurable =====
OPTEE_MANIFEST_URL="${OPTEE_MANIFEST_URL:-https://github.com/OP-TEE/manifest.git}"
OPTEE_MANIFEST_BRANCH="${OPTEE_MANIFEST_BRANCH:-master}"   # 可改成 stable 分支或某 tag
OPTEE_MANIFEST_FILE="${OPTEE_MANIFEST_FILE:-qemu_v8.xml}"  # 也可用 default.xml

# ===== Paths =====
BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
OPTEE_ROOT="${BASEDIR}/third_party/optee"       # <— 这里用 manifest 根目录
BUILD_DIR="${OPTEE_ROOT}/build"                  # repo 同步后会有 build/ 子仓库
EXPORT_TA="${BUILD_DIR}/optee_os/out/arm/export-ta_arm64"

# 确保依赖（包含 repo）
"${BASEDIR}/scripts/install_deps_ubuntu.sh"

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

# 导出 TA DevKit
if [ ! -d "${EXPORT_TA}" ]; then
  echo "TA devkit not found at ${EXPORT_TA}" >&2
  exit 1
fi

# 为工程的其它脚本导出统一变量
cat > "${BASEDIR}/scripts/env-optee-qemu.sh" <<EOF
#!/usr/bin/env bash
export BASEDIR="${BASEDIR}"
export OPTEE_BUILD_DIR="${BUILD_DIR}"
export OPTEE_OS_EXPORT="${EXPORT_TA}"
export TA_DEV_KIT_DIR="${EXPORT_TA}"
export CROSS_COMPILE=aarch64-linux-gnu-
export QEMU_SSH_PORT=10022
export QEMU_GUEST_USER=root
export QEMU_GUEST_PASS=root
EOF
chmod +x "${BASEDIR}/scripts/env-optee-qemu.sh"

echo "[optee] setup done. TA_DEV_KIT_DIR=${EXPORT_TA}"

# OP-TEE (qemu-v8) 使用指南（arm64-only）

## 初始化（一次）
```bash
make deps
make optee
# 生成并导出 arm64 TA DevKit：third_party/optee/optee_os/out/arm/export-ta_arm64
```

## 构建 TA/TC
```bash
make ta            # 仅 arm64 TA
make tc-aarch64    # aarch64 用户态程序（自动探测/构建 optee_client 导出）
```

## 启动与部署
```bash
# 交互式（前台）启动：进入 QEMU 控制台，可按 'c' 继续 normal world
make qemu   # 自动选择空闲 GDB 端口，避免 1234 冲突

# 后台启动并等待 SSH（用于自动化）：
make qemu.bg

make deploy        # 推送 TA 与 TC 到 QEMU
make selftest      # 在 QEMU 内运行自测（签名/哈希/AEAD）
```

可透传 QEMU 额外参数（例如 9p 共享目录）：
```bash
make qemu QEMU_EXTRA_ARGS="-fsdev local,id=fs0,path=/home/ldx1/gshare_dir,security_model=none -device virtio-9p-device,fsdev=fs0,mount_tag=host"
```

## 环境脚本
- `scripts/env-optee-qemu.sh` 会动态解析工程根目录并导出：
  - `TA_DEV_KIT_DIR=$REPO_ROOT/third_party/optee/optee_os/out/arm/export-ta_arm64`
  - 自动探测 `OPTEE_CLIENT_EXPORT`（优先 Buildroot sysroot；否则使用 `optee_client/out/export/usr` 或 `build/optee_client/out/export/usr`）。
  - `CROSS_COMPILE=aarch64-linux-gnu-`
- 若未探测到 `OPTEE_CLIENT_EXPORT`，`make tc-aarch64` 会自动调用 `scripts/setup_optee_env.sh --client-only` 构建并安装 `optee_client`，然后继续编译。
 - SSH：默认宿主机端口 `QEMU_SSH_PORT=10022` 会自动转发到来宾 22，可 `source scripts/env-optee-qemu.sh` 后直接 `ssh -p $QEMU_SSH_PORT root@127.0.0.1` 登录。

## 排错
- 出现 `-mthumb/-mfloat-abi=hard`：误触发 32 位 TA 构建。当前流程已禁用 `ta_arm32`；如遇旧缓存，重新 `make optee` 后再 `make ta`。
- `make tc-aarch64` 报 `tee_client_api.h not found`：运行 `scripts/setup_optee_env.sh --client-only` 或直接重试 `make tc-aarch64` 触发自动构建。
- `make deploy` 报 BASEDIR/路径问题：新脚本已改为 `REPO_ROOT`，请 `source scripts/env-optee-qemu.sh` 并重试。
- 看到 `gnome-terminal: -x 已弃用` 警告：来自上游 run-only 打开的终端参数，属无害提示，可忽略。

## 示例：RA‑TLS
```bash
# 宿主生成证书
bash scripts/gencert.sh  # 生成 server.crt / server.key

# 部署并登录来宾（默认 SSH 端口 10022）
make deploy
source scripts/env-optee-qemu.sh
sshpass -p "$QEMU_GUEST_PASS" ssh -p $QEMU_SSH_PORT -o StrictHostKeyChecking=no $QEMU_GUEST_USER@127.0.0.1

# 在来宾运行
/root/ratls_server 0.0.0.0 8443 /root/server.crt /root/server.key &> /root/ratls_server.log &
/root/ratls_client 127.0.0.1 8443
```

## 停止 QEMU
- 前台（make qemu）：在 QEMU 控制台输入 `quit`；或宿主 `pkill -f qemu-system-aarch64`。
- 后台（make qemu.bg）：`make qemu.stop`。

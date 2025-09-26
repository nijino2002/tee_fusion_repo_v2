# 安装与使用（OP-TEE qemu-v8，arm64-only，Ubuntu 24.04）

## 先决条件
- Ubuntu 22.04/24.04（或兼容）
- 基础工具：git、gcc、cmake、repo、sshpass、aarch64 交叉工具链

运行一次依赖安装：
```bash
make deps
```

## 初始化 OP-TEE 环境（仅导出 arm64 TA DevKit）
```bash
make optee
# 结束后会生成 scripts/env-optee-qemu.sh 并导出：
# - TA_DEV_KIT_DIR=$REPO_ROOT/third_party/optee/optee_os/out/arm/export-ta_arm64
# - OPTEE_CLIENT_EXPORT=$REPO_ROOT/third_party/optee/optee_client/out/export/usr
```

## 构建 TA/TC
```bash
make ta            # 仅 arm64 TA
make tc-aarch64    # aarch64 用户态程序（自动探测/构建 optee_client 导出）
```

## 运行与部署
```bash
# 交互式（前台）启动：终端即为 QEMU 控制台，可按 'c' 继续 normal world
make qemu

# 后台启动并等待 SSH（自动化）：
make qemu.bg

make deploy        # 推送 TA 与 TC
make selftest      # 在 QEMU 内运行自测
```

可向 QEMU 透传附加参数（例如 9p 共享目录）：
```bash
make qemu QEMU_EXTRA_ARGS="-fsdev local,id=fs0,path=/home/ldx1/gshare_dir,security_model=none -device virtio-9p-device,fsdev=fs0,mount_tag=host"
```

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

## 常见问题
- aarch64 编译器提示 `-mthumb/-mfloat-abi=hard`：
  - 这是误触发 32 位 TA 构建。已默认禁用 `ta_arm32`，如遇旧缓存，请重新执行 `make optee` 再 `make ta`。
- `make tc-aarch64` 提示 `tee_client_api.h not found`：
  - 运行 `scripts/setup_optee_env.sh --client-only` 以构建并安装 `optee_client` 导出，或直接重试 `make tc-aarch64` 触发自动构建。
- `make deploy` 提示找不到路径：
  - 确认 `source scripts/env-optee-qemu.sh` 后，`echo $REPO_ROOT` 与 `TA_DEV_KIT_DIR` 指向正确目录。

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
make tc-aarch64    # aarch64 用户态程序
```

## 启动与部署
```bash
make qemu          # 启动 qemu-v8，并等待 SSH 就绪
make deploy        # 推送 TA 与 TC 到 QEMU
make selftest      # 在 QEMU 内运行自测（签名/哈希/AEAD）
```

## 环境脚本
- `scripts/env-optee-qemu.sh` 会动态解析工程根目录并导出：
  - `TA_DEV_KIT_DIR=$REPO_ROOT/third_party/optee/optee_os/out/arm/export-ta_arm64`
  - `OPTEE_CLIENT_EXPORT=$REPO_ROOT/third_party/optee/optee_client/out/export/usr`
  - `CROSS_COMPILE=aarch64-linux-gnu-`

## 排错
- 出现 `-mthumb/-mfloat-abi=hard`：误触发 32 位 TA 构建。重新 `make optee` 确保仅 `ta_arm64`，再 `make ta`。
- `make deploy` 报 BASEDIR/路径问题：新脚本已改为 `REPO_ROOT`，请 `source scripts/env-optee-qemu.sh` 并重试。

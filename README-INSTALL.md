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
make tc-aarch64    # aarch64 用户态程序
```

## 运行与部署
```bash
make qemu          # 启动 qemu-v8 并等待 SSH
make deploy        # 推送 TA 与 TC
make selftest      # 在 QEMU 内运行自测
```

## 常见问题
- aarch64 编译器提示 `-mthumb/-mfloat-abi=hard`：
  - 这是误触发 32 位 TA 构建。当前脚本已使用 `CFG_USER_TA_TARGETS=ta_arm64`，请重新执行 `make optee` 再 `make ta`。
- `make deploy` 提示找不到路径：
  - 确认 `source scripts/env-optee-qemu.sh` 后，`echo $REPO_ROOT` 与 `TA_DEV_KIT_DIR` 指向正确目录。

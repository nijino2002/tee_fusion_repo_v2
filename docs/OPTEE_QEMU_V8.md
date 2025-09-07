# OP-TEE (qemu-v8) 使用指南（简版）
1) 使用 OP-TEE 官方 build 拉起 qemu-v8，得到 `optee_os/out/arm/export-ta_arm64`。
2) 构建 TA：
   ```bash
   export TA_DEV_KIT_DIR=/path/to/optee_os/out/arm/export-ta_arm64
   export CROSS_COMPILE=aarch64-linux-gnu-
   make -C optee/ta
   # 产物：7a9b3b24-3e2f-4d5f-912d-8b7c1355629a.ta → 拷入 /lib/optee_armtz/
   ```
3) 在 Normal World 编译并运行示例（确保安装 optee-client/libteec-dev 与 libssl-dev）。

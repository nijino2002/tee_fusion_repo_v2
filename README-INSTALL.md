# OP-TEE qemu-v8 Build Addon (Ubuntu 24.04)

## 使用方法
1. 覆盖你的工程根目录：
   - 将此包内的 `CMakeLists.txt` 覆盖根目录同名文件；
   - 将 `scripts/` 与顶层 `Makefile` 拷入工程根目录；

2. 安装依赖（一次）：
   ```bash
   make deps
   ```

3. 拉取并构建 OP-TEE (qemu-v8) 环境：
   ```bash
   make optee
   ```

4. 构建 TA：
   ```bash
   make ta
   ```

5. 交叉编译 TC（aarch64）：
   ```bash
   make tc-aarch64
   ```

6. 启动 QEMU、部署并自测：
   ```bash
   make qemu
   make deploy
   make selftest
   ```

> 预期在 QEMU 内看到 `selftest_crypto` 通过（签名/哈希/AEAD）。

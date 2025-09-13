# tee-fusion — Combo A (TDX / OP-TEE / Keystone) — Full Scaffold

这是一个**跨平台 TEE 融合运行时的工程骨架**，目标是让可信应用（TA/TC）不依赖任何具体 TEE 实现，通过统一 API 在不同平台（TDX / OP-TEE / Keystone）上无差别运行。

## 目录结构
- `include/`：统一 API 头文件，应用只依赖这里，不感知底层差异  
- `core/`：平台无关核心逻辑  
  - `api/`：API glue，把统一接口路由到适配层  
  - `evidence/`：U-Evidence 构建与 claims 映射  
  - `util/`：最小 CBOR/COSE 库  
- `adapters/`：平台适配层  
  - `optee/`：OP-TEE 客户端适配器（CA 侧）  
  - `tdx/`：Intel TDX 适配器（占位，用于接 QGS/DCAP）  
  - `keystone/`：RISC-V Keystone 适配器（占位，用于接 enclave report）  
- `optee/ta/`：OP-TEE TA 骨架（qemu-v8），用 Internal API 实现签名/哈希/AEAD  
- `examples/`：示例程序  
  - `ratls/`：RA-TLS server/client  
  - `selftest/`：自测（签名/哈希/AEAD）  
- `tests/`：单元测试（CBOR 等）  
- `scripts/`：自动化脚本  
  - `install_deps_ubuntu.sh`：安装依赖  
  - `setup_optee_qemu_v8.sh`：拉取并编译 OP-TEE (qemu-v8)  
  - `build_ta.sh` / `build_tc_aarch64.sh`：构建 TA 与交叉编 TC  
  - `run_qemu.sh` / `push_artifacts.sh`：启动 QEMU 并部署产物  
  - `gencert.sh`：生成 TLS 证书  
- `docs/`：额外文档（OP-TEE 使用说明）  
- `CMakeLists.txt`：CMake 构建配置  
- `Makefile`：顶层一键入口  
- `README.md`：本说明  

## 特点
- **统一 API**：应用调用 `tf_key_sign`、`tf_hash`、`tf_aead_seal/open` 等接口，而不是平台专用函数  
- **解耦设计**：平台相关逻辑集中在 `adapters/*` 和 OP-TEE 的 `ta/`  
- **可扩展性**：可逐步补全 TDX/Keystone adapter 与可信侧实现，而不影响应用代码  
- **可验证性**：已在 OP-TEE (qemu-v8) 跑通签名/哈希/AEAD，自测用例全部通过  

## 快速开始（主机侧构建）
```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config libssl-dev
mkdir build && cd build
cmake -DTEE_PLATFORM=tdx ..    # 或 -DTEE_PLATFORM=optee / keystone
make -j$(nproc)

../scripts/gencert.sh
./bin/ratls_server 127.0.0.1 8443 ../server.crt ../server.key
./bin/ratls_client 127.0.0.1 8443
```

## 完整流程（OP-TEE qemu-v8，arm64-only）
```bash
make deps          # 安装依赖（含 repo 工具）
make optee         # 拉取并构建 OP-TEE（自动生成 arm64 TA DevKit）
make ta            # 构建 TA（仅 arm64）
make tc-aarch64    # 交叉编译 TC（aarch64）
make qemu          # 启动 QEMU 并等待 SSH 就绪
make deploy        # 推送 TA 与 TC 到 QEMU 客户机
make selftest      # 在 QEMU 内运行自测（签名/哈希/AEAD）
```

要点说明：
- 仅构建 64 位 TA：内部使用 `CFG_USER_TA_TARGETS=ta_arm64`，并导出 `optee_os/out/arm/export-ta_arm64`。
- 环境脚本：`scripts/env-optee-qemu.sh` 动态解析 `REPO_ROOT`，导出 `TA_DEV_KIT_DIR`、`OPTEE_CLIENT_EXPORT` 等。
- 常见报错（已修复）：若出现 aarch64 编译器报 `-mthumb/-mfloat-abi=hard`，说明误触发了 32 位构建。当前流程已彻底禁用 ta_arm32。

更多说明与排错参见：`docs/OPTEE_QEMU_V8.md`。

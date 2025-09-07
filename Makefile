# ===== tee-fusion top-level Makefile (addon) =====
SHELL := /bin/bash

.PHONY: help deps optee ta tc-aarch64 qemu qemu.stop deploy selftest clean distclean

help:
	@echo "Targets:"
	@echo "  make deps         - 安装 Ubuntu 依赖（一次性）"
	@echo "  make optee        - 自动拉取并编译 OP-TEE qemu-v8 环境"
	@echo "  make ta           - 构建 OP-TEE TA (.ta)"
	@echo "  make tc-aarch64   - 交叉编译 TC (aarch64) 以在 QEMU 客户机执行"
	@echo "  make qemu         - 启动 OP-TEE qemu-v8（后台）并等待 SSH 就绪"
	@echo "  make deploy       - 将 TA 和 TC 推送进 QEMU 客户机"
	@echo "  make selftest     - 在 QEMU 内运行自测（签名/哈希/AEAD）"
	@echo "  make qemu.stop    - 关闭 QEMU"
	@echo "  make clean        - 清理主工程 build 目录"
	@echo "  make distclean    - 额外清理 OP-TEE build 目录"

deps:
	./scripts/install_deps_ubuntu.sh

optee:
	./scripts/setup_optee_qemu_v8.sh

ta:
	./scripts/build_ta.sh

tc-aarch64:
	./scripts/build_tc_aarch64.sh

qemu:
	./scripts/run_qemu.sh

deploy:
	./scripts/push_artifacts.sh

selftest:
	@echo "[selftest] running inside QEMU ..."
	@source ./scripts/env-optee-qemu.sh && \
	sshpass -p "$$QEMU_GUEST_PASS" ssh -p $$QEMU_SSH_PORT -o StrictHostKeyChecking=no \
	$$QEMU_GUEST_USER@127.0.0.1 "/root/selftest_crypto || true"

qemu.stop:
	@source ./scripts/env-optee-qemu.sh; \
	if [ -f "$$OPTEE_BUILD_DIR/.qemu_pid" ]; then \
	  PID=$$(cat "$$OPTEE_BUILD_DIR/.qemu_pid"); echo "[qemu] kill $$PID"; kill $$PID || true; \
	  rm -f "$$OPTEE_BUILD_DIR/.qemu_pid"; \
	else echo "[qemu] no pid file"; fi

clean:
	rm -rf build build-aarch64

distclean: clean
	rm -rf third_party/optee_build

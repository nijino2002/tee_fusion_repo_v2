# 业务 TA 源（只调 SAPI，不碰 TEE_*）
srcs-y += optee_fusion_ta.c

# OP-TEE 平台后端（把 SAPI 映射到 TEE_*）
srcs-y += backend/optee_sapi.c

# 头文件检索路径（从 optee/ta/ 相对路径写法）
global-incdirs-y += .
global-incdirs-y += ../../include   # 确保能找到 <tee_sapi.h> / <tee_fusion_ex.h>
global-incdirs-y += ../../adapters/optee

cflags-y += -Wall -Wextra

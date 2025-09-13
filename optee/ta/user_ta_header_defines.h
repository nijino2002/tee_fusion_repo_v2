#ifndef USER_TA_HEADER_DEFINES_H
#define USER_TA_HEADER_DEFINES_H

#include "optee_fusion_ta_uuid.h"   // 来自 adapters/optee/

#define TA_UUID            TA_OPTEE_FUSION_UUID
#define TA_FLAGS           (TA_FLAG_EXEC_DDR | TA_FLAG_SINGLE_INSTANCE | TA_FLAG_MULTI_SESSION | TA_FLAG_INSTANCE_KEEP_ALIVE)
// #define TA_FLAGS           (TA_FLAG_EXEC_DDR | TA_FLAG_SINGLE_INSTANCE | TA_FLAG_MULTI_SESSION)
#define TA_STACK_SIZE      (32 * 1024)
#define TA_DATA_SIZE       (64 * 1024)
#define TA_DESCRIPTION     "TEE Fusion SAPI demo TA"
#define TA_VERSION         "0.1.0"

#endif /* USER_TA_HEADER_DEFINES_H */

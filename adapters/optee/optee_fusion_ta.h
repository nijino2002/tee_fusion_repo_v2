#pragma once
#define TA_CMD_GET_PSA_TOKEN   0x0001
#define TA_CMD_KEY_GEN         0x0002
#define TA_CMD_GET_PUBKEY_XY   0x0003
#define TA_CMD_KEY_SIGN        0x0004
#define TA_CMD_RAND            0x0005

/* new ops */
#define TA_CMD_HASH_SHA256     0x0006
#define TA_CMD_AEAD_SEAL       0x0007
#define TA_CMD_AEAD_OPEN       0x0008

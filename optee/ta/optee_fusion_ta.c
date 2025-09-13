
// Business TA that uses only the fusion SAPI (TEE-agnostic).
#include <tee_internal_api.h>
#include <tee_internal_api_extensions.h>
#include "tee_sapi.h"     // alias to tee_fusion_ex.h (SAPI only; backend is TEE-specific)
#include "optee_fusion_ta_uuid.h"
#include "../../adapters/optee/optee_fusion_ta.h" // command IDs for NW<->SW IPC

#define CMD_PING           0x0001
#define CMD_SHA256         0x0201
#define CMD_GCM_SEAL       0x0301
#define CMD_GCM_OPEN       0x0302

static TEE_Result do_sha256(uint32_t types, TEE_Param p[4]) {
    const uint32_t ex = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_OUTPUT,
                                        TEE_PARAM_TYPE_NONE,
                                        TEE_PARAM_TYPE_NONE);
    if (types != ex) return TEE_ERROR_BAD_PARAMETERS;
    if (p[1].memref.size < 32) return TEE_ERROR_SHORT_BUFFER;
    if (tee_hash(TEE_HASH_SHA256, p[0].memref.buffer, p[0].memref.size,
                 (uint8_t*)p[1].memref.buffer) != TEE_OK)
        return TEE_ERROR_GENERIC;
    p[1].memref.size = 32;
    return TEE_SUCCESS;
}

static TEE_Result do_gcm_seal(uint32_t t, TEE_Param p[4]) {
    const uint32_t ex = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_OUTPUT);
    if (t != ex) return TEE_ERROR_BAD_PARAMETERS;
    size_t outl = p[3].memref.size;
    tee_status_t s = tee_aead_seal(TEE_AEAD_AES256_GCM,
                                   p[1].memref.buffer, p[1].memref.size,
                                   (const uint8_t*)p[2].memref.buffer,
                                   p[0].memref.buffer, p[0].memref.size,
                                   p[3].memref.buffer, &outl);
    if (s != TEE_OK) return TEE_ERROR_GENERIC;
    p[3].memref.size = outl;
    return TEE_SUCCESS;
}

static TEE_Result do_gcm_open(uint32_t t, TEE_Param p[4]) {
    const uint32_t ex = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_INOUT);
    if (t != ex) return TEE_ERROR_BAD_PARAMETERS;
    size_t outl = p[3].memref.size;
    tee_status_t s = tee_aead_open(TEE_AEAD_AES256_GCM,
                                   p[1].memref.buffer, p[1].memref.size,
                                   (const uint8_t*)p[2].memref.buffer,
                                   p[0].memref.buffer, p[0].memref.size,
                                   p[3].memref.buffer, &outl);
    if (s != TEE_OK)
        return TEE_ERROR_SECURITY; // 统一映射为 MAC 无效

    p[3].memref.size = outl;
    return TEE_SUCCESS;
}

/* ---- Keypair + Sign + Pubkey (P-256) via SAPI backend ---- */
static TEE_Result do_key_gen(void)
{ return tee_sapi_key_generate_p256() == TEE_OK ? TEE_SUCCESS : TEE_ERROR_GENERIC; }

static TEE_Result do_get_pubkey_xy(uint32_t types, TEE_Param p[4])
{
    const uint32_t ex = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_OUTPUT,
                                        TEE_PARAM_TYPE_NONE,
                                        TEE_PARAM_TYPE_NONE,
                                        TEE_PARAM_TYPE_NONE);
    if (types != ex)
        return TEE_ERROR_BAD_PARAMETERS;
    if (p[0].memref.size < 64)
        return TEE_ERROR_SHORT_BUFFER;
    uint8_t xy[64];
    tee_status_t s = tee_sapi_get_pubkey_xy(xy);
    if (s != TEE_OK)
        return TEE_ERROR_GENERIC;
    TEE_MemMove(p[0].memref.buffer, xy, 64);
    p[0].memref.size = 64;
    return TEE_SUCCESS;
}

static TEE_Result do_key_sign(uint32_t types, TEE_Param p[4])
{
    const uint32_t ex = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_OUTPUT,
                                        TEE_PARAM_TYPE_NONE,
                                        TEE_PARAM_TYPE_NONE);
    if (types != ex)
        return TEE_ERROR_BAD_PARAMETERS;
    size_t sl = p[1].memref.size;
    tee_status_t s = tee_sapi_sign_der(p[0].memref.buffer, p[0].memref.size,
                                       p[1].memref.buffer, &sl);
    if (s == TEE_ENOMEM) {
        p[1].memref.size = sl;
        return TEE_ERROR_SHORT_BUFFER;
    }
    if (s != TEE_OK)
        return TEE_ERROR_GENERIC;
    p[1].memref.size = sl;
    return TEE_SUCCESS;
}

static TEE_Result do_rand(uint32_t types, TEE_Param p[4])
{
    const uint32_t ex = TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_INPUT,
                                        TEE_PARAM_TYPE_MEMREF_OUTPUT,
                                        TEE_PARAM_TYPE_NONE,
                                        TEE_PARAM_TYPE_NONE);
    if (types != ex)
        return TEE_ERROR_BAD_PARAMETERS;
    uint32_t n = p[0].value.a;
    if (p[1].memref.size < n)
        return TEE_ERROR_SHORT_BUFFER;
    if (tee_sapi_rand_bytes(p[1].memref.buffer, n) != TEE_OK)
        return TEE_ERROR_GENERIC;
    p[1].memref.size = n;
    return TEE_SUCCESS;
}

/* TA lifecycle */
TEE_Result TA_CreateEntryPoint(void)  { return TEE_SUCCESS; }
void        TA_DestroyEntryPoint(void){}

TEE_Result TA_OpenSessionEntryPoint(uint32_t t, TEE_Param p[4], void **s) {
    (void)t; (void)p; (void)s; return TEE_SUCCESS;
}
void TA_CloseSessionEntryPoint(void *s){ (void)s; }

TEE_Result TA_InvokeCommandEntryPoint(void *s, uint32_t cmd, uint32_t types, TEE_Param p[4]) {
    (void)s;
    switch (cmd) {
    case CMD_PING:                    return TEE_SUCCESS;
    /* Accept both legacy CMD_* and new TA_CMD_* ids for portability */
    case CMD_SHA256:
    case TA_CMD_HASH_SHA256:          return do_sha256(types, p);
    case CMD_GCM_SEAL:
    case TA_CMD_AEAD_SEAL:            return do_gcm_seal(types, p);
    case CMD_GCM_OPEN:
    case TA_CMD_AEAD_OPEN:            return do_gcm_open(types, p);
    case TA_CMD_KEY_GEN:      return do_key_gen();
    case TA_CMD_GET_PUBKEY_XY:return do_get_pubkey_xy(types, p);
    case TA_CMD_KEY_SIGN:     return do_key_sign(types, p);
    case TA_CMD_RAND:         return do_rand(types, p);
    default:            return TEE_ERROR_NOT_SUPPORTED;
    }
}

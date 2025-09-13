// optee/ta/backend/optee_sapi.c
#include <tee_internal_api.h>
#include <tee_internal_api_extensions.h>
#include "tee_sapi.h"          // 实际上会转到 tee_fusion_ex.h
// 若你不创建 tee_sapi.h，也可直接 #include "tee_fusion_ex.h"

tee_status_t tee_hash(tee_hash_alg_t alg,
                      const void* msg, size_t msg_len,
                      uint8_t out_digest[32]) {
    if (alg != TEE_HASH_SHA256 || !out_digest) return TEE_EINVAL;

    TEE_OperationHandle op = TEE_HANDLE_NULL;
    TEE_Result r = TEE_AllocateOperation(&op, TEE_ALG_SHA256, TEE_MODE_DIGEST, 0);
    if (r != TEE_SUCCESS) return TEE_EINTERNAL;

    size_t out_len = 32;
    r = TEE_DigestDoFinal(op, (void*)msg, msg_len, out_digest, &out_len);
    TEE_FreeOperation(op);
    if (r != TEE_SUCCESS || out_len != 32) return TEE_EINTERNAL;

    return TEE_OK;
}

/* 固定 AES-256-GCM（tag 16 字节） */
static TEE_ObjectHandle s_aes_key = TEE_HANDLE_NULL;

static TEE_Result ensure_aes_key_256(void) {
    if (s_aes_key != TEE_HANDLE_NULL) return TEE_SUCCESS;
    TEE_Result r = TEE_AllocateTransientObject(TEE_TYPE_AES, 256, &s_aes_key);
    if (r) return r;
    uint8_t key[32];
    TEE_GenerateRandom(key, sizeof(key));
    TEE_Attribute a;
    TEE_InitRefAttribute(&a, TEE_ATTR_SECRET_VALUE, key, sizeof(key));
    r = TEE_PopulateTransientObject(s_aes_key, &a, 1);
    TEE_MemFill(key, 0, sizeof(key));
    if (r) { TEE_FreeTransientObject(s_aes_key); s_aes_key = TEE_HANDLE_NULL; }
    return r;
}

tee_status_t tee_aead_seal(tee_aead_alg_t alg,
                           const uint8_t* aad, size_t aad_len,
                           const uint8_t nonce[12],
                           const uint8_t* pt, size_t pt_len,
                           uint8_t* out_ct, size_t* out_ct_len) {
    if (alg != TEE_AEAD_AES256_GCM || !nonce || !pt || !out_ct || !out_ct_len)
        return TEE_EINVAL;

    /* 输出应至少 pt_len + 16（tag） */
    if (*out_ct_len < pt_len + 16) return TEE_EINVAL;

    TEE_Result r = ensure_aes_key_256(); if (r) return TEE_EINTERNAL;

    TEE_OperationHandle op = TEE_HANDLE_NULL;
    r = TEE_AllocateOperation(&op, TEE_ALG_AES_GCM, TEE_MODE_ENCRYPT, 256);
    if (r) return TEE_EINTERNAL;

    r = TEE_SetOperationKey(op, s_aes_key);
    if (r) { TEE_FreeOperation(op); return TEE_EINTERNAL; }

    /* GCM 初始化参数的 bit 计数 */
    TEE_AEInit(op, (void*)nonce, 12, 16 * 8, aad_len * 8, pt_len * 8);
    if (aad && aad_len) TEE_AEUpdateAAD(op, (void*)aad, aad_len);

    size_t ct_len = pt_len;
    size_t tag_len = 16;
    r = TEE_AEEncryptFinal(op, (void*)pt, pt_len,
                           out_ct, &ct_len,
                           out_ct + ct_len, &tag_len);
    TEE_FreeOperation(op);
    if (r) return TEE_EINTERNAL;

    *out_ct_len = ct_len + tag_len;
    return TEE_OK;
}

tee_status_t tee_aead_open(tee_aead_alg_t alg,
                           const uint8_t* aad, size_t aad_len,
                           const uint8_t nonce[12],
                           const uint8_t* ct, size_t ct_len,
                           uint8_t* out_pt, size_t* out_pt_len) {
    if (alg != TEE_AEAD_AES256_GCM || !nonce || !ct || !out_pt || !out_pt_len)
        return TEE_EINVAL;
    if (ct_len < 16) return TEE_EINVAL;

    TEE_Result r = ensure_aes_key_256(); if (r) return TEE_EINTERNAL;

    size_t data_len = ct_len - 16;
    const uint8_t* tag = ct + data_len;

    TEE_OperationHandle op = TEE_HANDLE_NULL;
    r = TEE_AllocateOperation(&op, TEE_ALG_AES_GCM, TEE_MODE_DECRYPT, 256);
    if (r) return TEE_EINTERNAL;
    r = TEE_SetOperationKey(op, s_aes_key);
    if (r) { TEE_FreeOperation(op); return TEE_EINTERNAL; }

    TEE_AEInit(op, (void*)nonce, 12, 16 * 8, aad_len * 8, data_len * 8);
    if (aad && aad_len) TEE_AEUpdateAAD(op, (void*)aad, aad_len);

    size_t out_len = *out_pt_len;
    r = TEE_AEDecryptFinal(op, ct, data_len, out_pt, &out_len, (void*)tag, 16);
    TEE_FreeOperation(op);
    if (r) return (r == TEE_ERROR_MAC_INVALID) ? TEE_EINVAL : TEE_EINTERNAL;

    *out_pt_len = out_len;
    return TEE_OK;
}

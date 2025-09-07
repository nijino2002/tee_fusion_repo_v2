#include <tee_internal_api.h>
#include <tee_internal_api_extensions.h>
#include "../../adapters/optee/optee_fusion_ta.h"

/* --- ECDSA key (existing) --- */
static TEE_ObjectHandle g_key = TEE_HANDLE_NULL;

/* --- AES-256-GCM key (demo) --- */
static TEE_ObjectHandle g_aes_key = TEE_HANDLE_NULL;
static const uint32_t G_TAG_BITS = 128; /* 16 bytes tag */

static TEE_Result ensure_ecdsa_key(void){
    if (g_key != TEE_HANDLE_NULL) return TEE_SUCCESS;
    TEE_Result res = TEE_AllocateTransientObject(TEE_TYPE_ECDSA_KEYPAIR, 256, &g_key);
    if (res != TEE_SUCCESS) return res;
    TEE_Attribute attrs[1];
    TEE_InitValueAttribute(&attrs[0], TEE_ATTR_ECC_CURVE, TEE_ECC_CURVE_NIST_P256, 0);
    return TEE_GenerateKey(g_key, 256, attrs, 1);
}

static TEE_Result ensure_aes_key(void){
    if (g_aes_key != TEE_HANDLE_NULL) return TEE_SUCCESS;
    TEE_Result res = TEE_AllocateTransientObject(TEE_TYPE_AES, 256, &g_aes_key);
    if (res != TEE_SUCCESS) return res;
    uint8_t key[32]; TEE_GenerateRandom(key, sizeof(key));
    TEE_Attribute a; TEE_InitRefAttribute(&a, TEE_ATTR_SECRET_VALUE, key, sizeof(key));
    return TEE_PopulateTransientObject(g_aes_key, &a, 1);
}

/* --- Commands --- */
static TEE_Result cmd_key_gen(uint32_t ptypes, TEE_Param params[4]){
    (void)ptypes; (void)params;
    if (g_key != TEE_HANDLE_NULL) { TEE_FreeTransientObject(g_key); g_key = TEE_HANDLE_NULL; }
    return ensure_ecdsa_key();
}

static TEE_Result cmd_get_pubkey_xy(uint32_t ptypes, TEE_Param params[4]){
    if (ptypes != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_OUTPUT, 0, 0, 0))
        return TEE_ERROR_BAD_PARAMETERS;
    TEE_Result res = ensure_ecdsa_key(); if (res != TEE_SUCCESS) return res;
    uint8_t x[32]={0}, y[32]={0}; uint32_t xl=sizeof(x), yl=sizeof(y);
    res = TEE_GetObjectBufferAttribute(g_key, TEE_ATTR_ECC_PUBLIC_VALUE_X, x, &xl); if (res != TEE_SUCCESS) return res;
    res = TEE_GetObjectBufferAttribute(g_key, TEE_ATTR_ECC_PUBLIC_VALUE_Y, y, &yl); if (res != TEE_SUCCESS) return res;
    if (params[0].memref.size < xl+yl) { params[0].memref.size = xl+yl; return TEE_ERROR_SHORT_BUFFER; }
    TEE_MemMove(params[0].memref.buffer, x, xl);
    TEE_MemMove((uint8_t*)params[0].memref.buffer + xl, y, yl);
    params[0].memref.size = xl + yl; return TEE_SUCCESS;
}

static TEE_Result cmd_key_sign(uint32_t ptypes, TEE_Param params[4]){
    if (ptypes != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT, TEE_PARAM_TYPE_MEMREF_OUTPUT, 0, 0))
        return TEE_ERROR_BAD_PARAMETERS;
    TEE_Result res = ensure_ecdsa_key(); if (res != TEE_SUCCESS) return res;

    TEE_OperationHandle dig = TEE_HANDLE_NULL;
    TEE_OperationHandle sig = TEE_HANDLE_NULL;
    uint8_t digest[32]; uint32_t dlen = sizeof(digest);

    res = TEE_AllocateOperation(&dig, TEE_ALG_SHA256, TEE_MODE_DIGEST, 0);
    if (res != TEE_SUCCESS) goto out;
    TEE_DigestDoFinal(dig, params[0].memref.buffer, params[0].memref.size, digest, &dlen);

    res = TEE_AllocateOperation(&sig, TEE_ALG_ECDSA, TEE_MODE_SIGN, 256);
    if (res != TEE_SUCCESS) goto out;
    res = TEE_SetOperationKey(sig, g_key);
    if (res != TEE_SUCCESS) goto out;

    uint32_t out_sz = params[1].memref.size;
    res = TEE_AsymmetricSignDigest(sig, NULL, 0, digest, dlen, params[1].memref.buffer, &out_sz);
    if (res == TEE_ERROR_SHORT_BUFFER) { params[1].memref.size = out_sz; goto out; }
    if (res != TEE_SUCCESS) goto out;
    params[1].memref.size = out_sz;

out:
    if (dig) TEE_FreeOperation(dig);
    if (sig) TEE_FreeOperation(sig);
    return res;
}

static TEE_Result cmd_rand(uint32_t ptypes, TEE_Param params[4]){
    if (ptypes != TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_INPUT, TEE_PARAM_TYPE_MEMREF_OUTPUT, 0, 0))
        return TEE_ERROR_BAD_PARAMETERS;
    uint32_t need = params[0].value.a;
    if (params[1].memref.size < need) { params[1].memref.size = need; return TEE_ERROR_SHORT_BUFFER; }
    TEE_GenerateRandom(params[1].memref.buffer, need);
    params[1].memref.size = need; return TEE_SUCCESS;
}

static TEE_Result cmd_get_psa_token(uint32_t ptypes, TEE_Param params[4]){
    if (ptypes != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_OUTPUT, 0, 0, 0))
        return TEE_ERROR_BAD_PARAMETERS;
    const char token[] = "OPTEE_PSA_TOKEN_POC";
    uint32_t need = sizeof(token)-1;
    if (params[0].memref.size < need) { params[0].memref.size = need; return TEE_ERROR_SHORT_BUFFER; }
    TEE_MemMove(params[0].memref.buffer, token, need);
    params[0].memref.size = need; return TEE_SUCCESS;
}

/* --- new: HASH SHA-256 --- */
static TEE_Result cmd_hash_sha256(uint32_t ptypes, TEE_Param params[4]){
    if (ptypes != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT, TEE_PARAM_TYPE_MEMREF_OUTPUT, 0, 0))
        return TEE_ERROR_BAD_PARAMETERS;
    TEE_OperationHandle dig = TEE_HANDLE_NULL;
    TEE_Result res = TEE_AllocateOperation(&dig, TEE_ALG_SHA256, TEE_MODE_DIGEST, 0);
    if (res != TEE_SUCCESS) return res;
    uint8_t out[32]; uint32_t olen = sizeof(out);
    TEE_DigestDoFinal(dig, params[0].memref.buffer, params[0].memref.size, out, &olen);
    if (params[1].memref.size < olen){ params[1].memref.size = olen; res = TEE_ERROR_SHORT_BUFFER; goto out; }
    TEE_MemMove(params[1].memref.buffer, out, olen);
    params[1].memref.size = olen; res = TEE_SUCCESS;
out:
    TEE_FreeOperation(dig);
    return res;
}

/* --- new: AEAD AES-256-GCM (seal/open) --- */
static TEE_Result cmd_aead_seal(uint32_t ptypes, TEE_Param params[4]){
    if (ptypes != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,  /* nonce(12) */
                                  TEE_PARAM_TYPE_MEMREF_INPUT,  /* AAD */
                                  TEE_PARAM_TYPE_MEMREF_INPUT,  /* PT */
                                  TEE_PARAM_TYPE_MEMREF_OUTPUT))/* CT||TAG */
        return TEE_ERROR_BAD_PARAMETERS;

    TEE_Result res = ensure_aes_key(); if (res != TEE_SUCCESS) return res;

    TEE_OperationHandle op = TEE_HANDLE_NULL;
    res = TEE_AllocateOperation(&op, TEE_ALG_AES_GCM, TEE_MODE_ENCRYPT, 256);
    if (res != TEE_SUCCESS) return res;
    res = TEE_SetOperationKey(op, g_aes_key); if (res != TEE_SUCCESS) goto out;
    res = TEE_AEInit(op, params[0].memref.buffer, params[0].memref.size, G_TAG_BITS, 0, 0);
    if (res != TEE_SUCCESS) goto out;
    if (params[1].memref.size) TEE_AEUpdateAAD(op, params[1].memref.buffer, params[1].memref.size);

    uint32_t pt_len = params[2].memref.size;
    uint32_t ct_need = pt_len + (G_TAG_BITS/8);
    if (params[3].memref.size < ct_need){ params[3].memref.size = ct_need; res = TEE_ERROR_SHORT_BUFFER; goto out; }

    uint8_t* ct = (uint8_t*)params[3].memref.buffer;
    uint32_t clen = pt_len, tag_len = G_TAG_BITS/8;
    res = TEE_AEEncryptFinal(op,
                             params[2].memref.buffer, pt_len,
                             ct, &clen,
                             ct + pt_len, &tag_len);
    if (res == TEE_SUCCESS) params[3].memref.size = pt_len + tag_len;
out:
    if (op) TEE_FreeOperation(op);
    return res;
}

static TEE_Result cmd_aead_open(uint32_t ptypes, TEE_Param params[4]){
    if (ptypes != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,  /* nonce */
                                  TEE_PARAM_TYPE_MEMREF_INPUT,  /* AAD */
                                  TEE_PARAM_TYPE_MEMREF_INPUT,  /* CT||TAG */
                                  TEE_PARAM_TYPE_MEMREF_OUTPUT))/* PT */
        return TEE_ERROR_BAD_PARAMETERS;

    TEE_Result res = ensure_aes_key(); if (res != TEE_SUCCESS) return res;
    if (params[2].memref.size < (G_TAG_BITS/8)) return TEE_ERROR_BAD_PARAMETERS;

    uint32_t total = params[2].memref.size;
    uint32_t pt_len = total - (G_TAG_BITS/8);
    uint8_t* in = (uint8_t*)params[2].memref.buffer;
    uint8_t* tag = in + pt_len;
    uint32_t tag_len = G_TAG_BITS/8;

    if (params[3].memref.size < pt_len){ params[3].memref.size = pt_len; return TEE_ERROR_SHORT_BUFFER; }

    TEE_OperationHandle op = TEE_HANDLE_NULL;
    res = TEE_AllocateOperation(&op, TEE_ALG_AES_GCM, TEE_MODE_DECRYPT, 256);
    if (res != TEE_SUCCESS) return res;
    res = TEE_SetOperationKey(op, g_aes_key); if (res != TEE_SUCCESS) goto out;
    res = TEE_AEInit(op, params[0].memref.buffer, params[0].memref.size, G_TAG_BITS, 0, 0);
    if (res != TEE_SUCCESS) goto out;
    if (params[1].memref.size) TEE_AEUpdateAAD(op, params[1].memref.buffer, params[1].memref.size);

    uint32_t out_len = pt_len;
    res = TEE_AEDecryptFinal(op,
                             in, pt_len,
                             params[3].memref.buffer, &out_len,
                             tag, &tag_len);
    params[3].memref.size = out_len;
    if (res == TEE_ERROR_MAC_INVALID) res = TEE_ERROR_SECURITY;
out:
    if (op) TEE_FreeOperation(op);
    return res;
}

/* entry points */
TEE_Result TA_CreateEntryPoint(void){ return TEE_SUCCESS; }
void TA_DestroyEntryPoint(void){
    if (g_key != TEE_HANDLE_NULL) { TEE_FreeTransientObject(g_key); g_key = TEE_HANDLE_NULL; }
    if (g_aes_key != TEE_HANDLE_NULL) { TEE_FreeTransientObject(g_aes_key); g_aes_key = TEE_HANDLE_NULL; }
}
TEE_Result TA_OpenSessionEntryPoint(uint32_t ptypes, TEE_Param params[4], void** sess){ (void)ptypes; (void)params; (void)sess; return TEE_SUCCESS; }
void TA_CloseSessionEntryPoint(void* sess){ (void)sess; }
TEE_Result TA_InvokeCommandEntryPoint(void* sess, uint32_t cmd, uint32_t ptypes, TEE_Param params[4]){
    (void)sess;
    switch (cmd){
    case TA_CMD_GET_PSA_TOKEN:  return cmd_get_psa_token(ptypes, params);
    case TA_CMD_KEY_GEN:        return cmd_key_gen(ptypes, params);
    case TA_CMD_GET_PUBKEY_XY:  return cmd_get_pubkey_xy(ptypes, params);
    case TA_CMD_KEY_SIGN:       return cmd_key_sign(ptypes, params);
    case TA_CMD_RAND:           return cmd_rand(ptypes, params);
    case TA_CMD_HASH_SHA256:    return cmd_hash_sha256(ptypes, params);
    case TA_CMD_AEAD_SEAL:      return cmd_aead_seal(ptypes, params);
    case TA_CMD_AEAD_OPEN:      return cmd_aead_open(ptypes, params);
    default: return TEE_ERROR_NOT_SUPPORTED;
    }
}

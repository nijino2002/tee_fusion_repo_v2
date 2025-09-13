
// OP-TEE backend implementing the fusion SAPI (hash + AEAD + key + RNG) for TA side.
#include <tee_internal_api.h>
#include <tee_internal_api_extensions.h>
#include "tee_sapi.h"   // actually tee_fusion_ex.h

// Hash — SHA-256 only
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

// AEAD — AES-256-GCM with 16-byte tag using TEE_AE API
static TEE_ObjectHandle s_aes = TEE_HANDLE_NULL;

static TEE_Result ensure_aes_256(void)
{
    if (s_aes != TEE_HANDLE_NULL)
        return TEE_SUCCESS;
    TEE_Result r = TEE_AllocateTransientObject(TEE_TYPE_AES, 256, &s_aes);
    if (r)
        return r;
    static const uint8_t fixed_key[32] = { 0 }; /* demo key */
    TEE_Attribute a;
    TEE_InitRefAttribute(&a, TEE_ATTR_SECRET_VALUE, (void*)fixed_key, sizeof(fixed_key));
    r = TEE_PopulateTransientObject(s_aes, &a, 1);
    if (r) {
        TEE_FreeTransientObject(s_aes);
        s_aes = TEE_HANDLE_NULL;
    }
    return r;
}

tee_status_t tee_aead_seal(tee_aead_alg_t alg,
                           const uint8_t* aad, size_t aad_len,
                           const uint8_t nonce[12],
                           const uint8_t* pt, size_t pt_len,
                           uint8_t* out_ct, size_t* out_ct_len) {
    if (alg != TEE_AEAD_AES256_GCM || !nonce || !pt || !out_ct || !out_ct_len)
        return TEE_EINVAL;
    if (*out_ct_len < pt_len + 16) return TEE_EINVAL;

    if (ensure_aes_256())
        return TEE_EINTERNAL;
    if (*out_ct_len < pt_len + 16)
        return TEE_EINVAL;
    TEE_OperationHandle op = TEE_HANDLE_NULL;
    TEE_Result r = TEE_AllocateOperation(&op, TEE_ALG_AES_GCM, TEE_MODE_ENCRYPT, 256);
    if (r)
        return TEE_EINTERNAL;
    r = TEE_SetOperationKey(op, s_aes);
    if (r) {
        TEE_FreeOperation(op);
        return TEE_EINTERNAL;
    }
    /* tagLen in bits; AAD/payload lengths in bytes */
    TEE_AEInit(op, (void*)nonce, 12, 16*8, aad_len, pt_len);
    if (aad && aad_len)
        TEE_AEUpdateAAD(op, (void*)aad, aad_len);
    size_t ct_len = pt_len;
    size_t tag_len = 16;
    r = TEE_AEEncryptFinal(op, (void*)pt, pt_len,
                           out_ct, &ct_len,
                           out_ct + ct_len, &tag_len);
    TEE_FreeOperation(op);
    if (r)
        return TEE_EINTERNAL;
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

    if (ensure_aes_256())
        return TEE_EINTERNAL;
    if (ct_len < 16)
        return TEE_EINVAL;
    size_t data_len = ct_len - 16;
    const uint8_t* tag = ct + data_len;
    TEE_OperationHandle op = TEE_HANDLE_NULL;
    TEE_Result r = TEE_AllocateOperation(&op, TEE_ALG_AES_GCM, TEE_MODE_DECRYPT, 256);
    if (r)
        return TEE_EINTERNAL;
    r = TEE_SetOperationKey(op, s_aes);
    if (r) {
        TEE_FreeOperation(op);
        return TEE_EINTERNAL;
    }
    TEE_AEInit(op, (void*)nonce, 12, 16*8, aad_len, data_len);
    if (aad && aad_len)
        TEE_AEUpdateAAD(op, (void*)aad, aad_len);
    size_t out_len = *out_pt_len;
    r = TEE_AEDecryptFinal(op, ct, data_len, out_pt, &out_len, (void*)tag, 16);
    TEE_FreeOperation(op);
    if (r)
        return (r == TEE_ERROR_MAC_INVALID) ? TEE_EINVAL : TEE_EINTERNAL;
    *out_pt_len = out_len;
    return TEE_OK;
}

/* ---- Keypair + Sign + RNG (mbedTLS backend) ---- */
/* Allow access to context private members for grp/Q when needed */
#ifndef MBEDTLS_ALLOW_PRIVATE_ACCESS
#define MBEDTLS_ALLOW_PRIVATE_ACCESS 1
#endif
#include <mbedtls/ecdsa.h>
#include <mbedtls/ecp.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>
#include <mbedtls/sha256.h>

static mbedtls_ecdsa_context s_ecdsa;
static mbedtls_ctr_drbg_context s_drbg;
static mbedtls_entropy_context s_entropy;
static int s_kinit = 0;

static void rng_seed_once(void)
{
    if (s_kinit)
        return;
    mbedtls_ecdsa_init(&s_ecdsa);
    mbedtls_ctr_drbg_init(&s_drbg);
    mbedtls_entropy_init(&s_entropy);
    /* Seed DRBG with TEE RNG as entropy source */
    unsigned char seed[48];
    TEE_GenerateRandom(seed, sizeof(seed));
    mbedtls_ctr_drbg_seed(&s_drbg, mbedtls_entropy_func, &s_entropy, seed, sizeof(seed));
    TEE_MemFill(seed, 0, sizeof(seed));
    s_kinit = 1;
}

tee_status_t tee_sapi_key_generate_p256(void)
{
    rng_seed_once();
    mbedtls_ecdsa_free(&s_ecdsa);
    mbedtls_ecdsa_init(&s_ecdsa);
    if (mbedtls_ecdsa_genkey(&s_ecdsa, MBEDTLS_ECP_DP_SECP256R1,
                              mbedtls_ctr_drbg_random, &s_drbg) != 0)
        return TEE_EINTERNAL;
    return TEE_OK;
}

tee_status_t tee_sapi_get_pubkey_xy(uint8_t out_xy[64])
{
    if (!out_xy)
        return TEE_EINVAL;
    rng_seed_once();
    /* Export uncompressed point: 0x04 || X(32) || Y(32) */
    unsigned char pt[1 + 32 + 32];
    size_t olen = 0;
    if (mbedtls_ecp_point_write_binary(&s_ecdsa.MBEDTLS_PRIVATE(grp),
                                       &s_ecdsa.MBEDTLS_PRIVATE(Q),
                                       MBEDTLS_ECP_PF_UNCOMPRESSED,
                                       &olen, pt, sizeof(pt)) != 0)
        return TEE_EINTERNAL;
    if (olen != sizeof(pt) || pt[0] != 0x04)
        return TEE_EINTERNAL;
    TEE_MemMove(out_xy,      pt + 1, 32);
    TEE_MemMove(out_xy + 32, pt + 1 + 32, 32);
    return TEE_OK;
}

tee_status_t tee_sapi_sign_der(const void* msg, size_t msg_len,
                               uint8_t* out_sig, size_t* inout_sig_len)
{
    if (!msg || !out_sig || !inout_sig_len)
        return TEE_EINVAL;
    rng_seed_once();
    unsigned char dgst[32];
    /* mbedtls_sha256(input, ilen, output, is224=0) */
    if (mbedtls_sha256((const unsigned char*)msg, msg_len, dgst, 0) != 0)
        return TEE_EINTERNAL;
    size_t sig_len = 0;
    /* Write DER signature into caller buffer */
    if (mbedtls_ecdsa_write_signature(&s_ecdsa, MBEDTLS_MD_SHA256,
                                      dgst, sizeof(dgst),
                                      out_sig, *inout_sig_len, &sig_len,
                                      mbedtls_ctr_drbg_random, &s_drbg) != 0) {
        *inout_sig_len = sig_len; /* may contain required length */
        return TEE_ENOMEM;
    }
    *inout_sig_len = sig_len;
    return TEE_OK;
}

tee_status_t tee_sapi_rand_bytes(void* buf, size_t len)
{
    if (!buf || !len)
        return TEE_EINVAL;
    rng_seed_once();
    if (mbedtls_ctr_drbg_random(&s_drbg, buf, len) != 0)
        return TEE_EINTERNAL;
    return TEE_OK;
}

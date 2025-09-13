#pragma once
#include <stddef.h>
#include <stdint.h>
#include "tee_fusion_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* --- Hash --- */
typedef enum { TEE_HASH_SHA256 = 1 } tee_hash_alg_t;
tee_status_t tee_hash(tee_hash_alg_t alg, const void* msg, size_t msg_len,
                      uint8_t out_digest[32]);

/* --- AEAD (AES-256-GCM) --- */
typedef enum { TEE_AEAD_AES256_GCM = 1 } tee_aead_alg_t;
/* Seal: out_ct = ciphertext||tag(16B) */
tee_status_t tee_aead_seal(tee_aead_alg_t alg,
                           const uint8_t* aad, size_t aad_len,
                           const uint8_t nonce[12],
                           const uint8_t* pt, size_t pt_len,
                           uint8_t* out_ct, size_t* out_ct_len);

/* Open: verify tag and decrypt; TF_EINVAL if MAC invalid */
tee_status_t tee_aead_open(tee_aead_alg_t alg,
                           const uint8_t* aad, size_t aad_len,
                           const uint8_t nonce[12],
                           const uint8_t* ct, size_t ct_len,
                           uint8_t* out_pt, size_t* out_pt_len);

/* --- Key & RNG SAPI for TA side (TEE-agnostic API, platform-specific backend) --- */
/* Generate an EC P-256 keypair in the TA (kept internal to the TA) */
tee_status_t tee_sapi_key_generate_p256(void);
/* Export public key (X||Y), 64 bytes */
tee_status_t tee_sapi_get_pubkey_xy(uint8_t out_xy[64]);
/* Sign message (SHA-256 then ECDSA-P256), output DER signature */
tee_status_t tee_sapi_sign_der(const void* msg, size_t msg_len,
                               uint8_t* out_sig, size_t* inout_sig_len);
/* Fill buffer with cryptographically secure random bytes */
tee_status_t tee_sapi_rand_bytes(void* buf, size_t len);

#ifdef __cplusplus
}
#endif

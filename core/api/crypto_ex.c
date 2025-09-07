#include <string.h>
#include "../../include/tee_fusion_ex.h"
#include "../../include/tee_fusion.h"

/* adapter vtable symbol provided by platform adapter via tee_register_active_adapter */
typedef struct {
  tee_status_t (*get_report)(tee_buf_t*);
  tee_status_t (*fill_platform_claims)(const uint8_t*, size_t);
  tee_status_t (*key_new)(tee_key_algo_t, tee_attested_key_t*);
  tee_status_t (*key_sign)(const void*, size_t, uint8_t*, size_t*);
  tee_status_t (*rand_bytes)(void*, size_t);
  tee_status_t (*ocall)(uint32_t, const void*, size_t, void*, size_t*);
  tee_class_t  (*platform_id)(void);
  tee_status_t (*hash_sha256)(const void*, size_t, uint8_t out[32]);
  tee_status_t (*aead_seal)(const uint8_t*, size_t, const uint8_t[12],
                            const uint8_t*, size_t, uint8_t*, size_t*);
  tee_status_t (*aead_open)(const uint8_t*, size_t, const uint8_t[12],
                            const uint8_t*, size_t, uint8_t*, size_t*);
} tee_adapter_vt;

extern void tee_register_active_adapter(tee_adapter_vt* vt); /* ensures symbol linkage */
static tee_adapter_vt G;
__attribute__((constructor)) static void _tf_crypto_glue_ctor(void){ tee_register_active_adapter(&G); }

tee_status_t tee_hash(tee_hash_alg_t alg, const void* msg, size_t msg_len, uint8_t out_digest[32]){
  if(alg != TEE_HASH_SHA256) return TEE_ENOTSUP;
  if(!G.hash_sha256) return TEE_ENOTSUP;
  return G.hash_sha256(msg, msg_len, out_digest);
}

tee_status_t tee_aead_seal(tee_aead_alg_t alg,
                           const uint8_t* aad, size_t aad_len,
                           const uint8_t nonce[12],
                           const uint8_t* pt, size_t pt_len,
                           uint8_t* out_ct, size_t* out_ct_len){
  if(alg != TEE_AEAD_AES256_GCM) return TEE_ENOTSUP;
  if(!G.aead_seal) return TEE_ENOTSUP;
  return G.aead_seal(aad, aad_len, nonce, pt, pt_len, out_ct, out_ct_len);
}

tee_status_t tee_aead_open(tee_aead_alg_t alg,
                           const uint8_t* aad, size_t aad_len,
                           const uint8_t nonce[12],
                           const uint8_t* ct, size_t ct_len,
                           uint8_t* out_pt, size_t* out_pt_len){
  if(alg != TEE_AEAD_AES256_GCM) return TEE_ENOTSUP;
  if(!G.aead_open) return TEE_ENOTSUP;
  return G.aead_open(aad, aad_len, nonce, ct, ct_len, out_pt, out_pt_len);
}

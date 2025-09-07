#pragma once
#include <stddef.h>
#include <stdint.h>
#include "../include/tee_fusion.h"
#include "../include/tee_fusion_ex.h"

typedef struct {
  tee_status_t (*get_report)(tee_buf_t*);
  tee_status_t (*fill_platform_claims)(const uint8_t*, size_t);
  tee_status_t (*key_new)(tee_key_algo_t, tee_attested_key_t*);
  tee_status_t (*key_sign)(const void*, size_t, uint8_t*, size_t*);
  tee_status_t (*rand_bytes)(void*, size_t);
  tee_status_t (*ocall)(uint32_t, const void*, size_t, void*, size_t*);
  tee_class_t  (*platform_id)(void);

  /* --- new crypto ops --- */
  tee_status_t (*hash_sha256)(const void*, size_t, uint8_t out[32]);
  tee_status_t (*aead_seal)(const uint8_t* aad, size_t aad_len,
                            const uint8_t nonce[12],
                            const uint8_t* pt, size_t pt_len,
                            uint8_t* out_ct, size_t* out_ct_len);
  tee_status_t (*aead_open)(const uint8_t* aad, size_t aad_len,
                            const uint8_t nonce[12],
                            const uint8_t* ct, size_t ct_len,
                            uint8_t* out_pt, size_t* out_pt_len);
} tee_adapter_vt;

void tee_register_active_adapter(tee_adapter_vt* vt);

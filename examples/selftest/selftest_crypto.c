#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <openssl/evp.h>
#include <openssl/x509.h>
#include "../../include/tee_fusion.h"
#include "../../include/tee_fusion_ex.h"

static int verify_p256_der(const uint8_t* spki, size_t spki_len,
                           const uint8_t* msg, size_t msg_len,
                           const uint8_t* sig, size_t sig_len){
  const unsigned char* p = spki;
  EVP_PKEY* P = d2i_PUBKEY(NULL, &p, (long)spki_len);
  EVP_MD_CTX* C = EVP_MD_CTX_new();
  int ok = EVP_DigestVerifyInit(C, NULL, EVP_sha256(), NULL, P) == 1
        && EVP_DigestVerify(C, sig, sig_len, msg, msg_len) == 1;
  EVP_MD_CTX_free(C); EVP_PKEY_free(P);
  return ok;
}

int main(){
  printf("[selftest] start\n");
  /* 必须先初始化以注册适配器并建立与 TA 的会话 */
  tee_info_t info = {0};
  if (tee_init(NULL, &info) != TEE_OK) {
    fprintf(stderr, "[selftest] tee_init failed\n");
    return 1;
  }
  /* sign/verify */
  tee_attested_key_t k; uint8_t sig[128]; size_t sl=sizeof(sig);
  const char* m = "hello tee-fusion";
  assert(tee_key_generate(TEE_EC_P256, &k)==TEE_OK);
  assert(tee_key_sign(&k, m, strlen(m), sig, &sl)==TEE_OK);
  assert(verify_p256_der(k.pubkey, k.pubkey_len, (const uint8_t*)m, strlen(m), sig, sl));

  /* hash */
  uint8_t d1[32]; assert(tee_hash(TEE_HASH_SHA256, m, strlen(m), d1)==TEE_OK);
  printf("[selftest] sha256 ok\n");

  /* aead seal/open */
  const uint8_t aad[] = "ctx"; const uint8_t nonce[12] = {0,1,2,3,4,5,6,7,8,9,10,11};
  const uint8_t pt[] = "secret data";
  uint8_t ct[256]; size_t cl=sizeof(ct);
  assert(tee_aead_seal(TEE_AEAD_AES256_GCM, aad, sizeof(aad)-1, nonce, pt, sizeof(pt)-1, ct, &cl)==TEE_OK);
  uint8_t out[256]; size_t ol=sizeof(out);
  assert(tee_aead_open(TEE_AEAD_AES256_GCM, aad, sizeof(aad)-1, nonce, ct, cl, out, &ol)==TEE_OK);
  assert(ol==sizeof(pt)-1 && memcmp(out, pt, ol)==0);
  printf("[selftest] aead ok (seal/open)\n");

  /* tamper detection */
  ct[0]^=1; ol=sizeof(out);
  assert(tee_aead_open(TEE_AEAD_AES256_GCM, aad, sizeof(aad)-1, nonce, ct, cl, out, &ol)==TEE_EINVAL);
  printf("[selftest] tamper detection ok\n");

  printf("[selftest] all pass\n");
  tee_exit(0);
  return 0;
}

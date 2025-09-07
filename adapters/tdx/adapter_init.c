#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/rand.h>
#include "../adapter_iface.h"
#include "../../include/tee_fusion.h"

static int read_all(const char* path, uint8_t** out, size_t* out_len){
    FILE* f = fopen(path, "rb");
    if(!f) return 0;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    if(n <= 0) { fclose(f); return 0; }
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = (uint8_t*)malloc((size_t)n);
    if(!buf){ fclose(f); return 0; }
    if(fread(buf, 1, (size_t)n, f) != (size_t)n){ free(buf); fclose(f); return 0; }
    fclose(f);
    *out = buf; *out_len = (size_t)n;
    return 1;
}

static tee_status_t get_report(tee_buf_t* out){
    if(!out) return TEE_EINVAL;
    const char* p = getenv("TDX_QUOTE_FILE");
    if(p && *p){
        uint8_t* buf = NULL; size_t n = 0;
        if(read_all(p, &buf, &n)){
            out->ptr = buf; out->len = n; return TEE_OK;
        }
        return TEE_EINTERNAL;
    }
    out->ptr = NULL; out->len = 0;
    return TEE_OK;
}

extern void mapping_reset();
extern void mapping_set_common(const char*, const char*, int, unsigned int);
extern void mapping_set_sw_measurement(const uint8_t*, size_t);
extern void mapping_set_native_quote(const uint8_t*, size_t);

static tee_status_t fill_platform_claims(const uint8_t* rpt, size_t n){
    mapping_reset();
    mapping_set_common("Intel-TDX", "cvm", 0, 1);
    uint8_t meas[32] = {0};
    mapping_set_sw_measurement(meas, sizeof(meas));
    if(rpt && n) mapping_set_native_quote(rpt, n);
    return TEE_OK;
}

static tee_status_t rand_bytes(void* buf, size_t len){
    if(!buf || !len) return TEE_EINVAL;
    return RAND_bytes((unsigned char*)buf, (int)len)==1 ? TEE_OK : TEE_EINTERNAL;
}

static tee_status_t ocall(uint32_t op, const void* in, size_t ilen, void* out, size_t* olen){
    (void)op;
    if(!out || !olen) return TEE_EINVAL;
    size_t n = ilen < *olen ? ilen : *olen;
    if(in && n) memcpy(out, in, n);
    *olen = n;
    return TEE_OK;
}

static tee_status_t key_new(tee_key_algo_t a, tee_attested_key_t* out){ (void)a; (void)out; return TEE_ENOTSUP; }
static tee_status_t key_sign(const void* m, size_t n, uint8_t* sig, size_t* sl){ (void)m; (void)n; (void)sig; (void)sl; return TEE_ENOTSUP; }
static tee_class_t platform_id(void){ return TEE_CLASS_TDX; }

void tee_register_active_adapter(tee_adapter_vt* vt){
    vt->get_report = get_report;
    vt->fill_platform_claims = fill_platform_claims;
    vt->key_new  = key_new;
    vt->key_sign = key_sign;
    vt->rand_bytes = rand_bytes;
    vt->ocall = ocall;
    vt->platform_id = platform_id;
}

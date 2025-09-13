
#pragma once
/* tee_sapi.h — Thin alias for fusion SAPI.
 * We reuse tee_fusion_ex.h as the TEE-agnostic security API surface.
 * Business code (TA/TC) should include this header and never call TEE_* directly.
 */
#include "tee_fusion_ex.h"

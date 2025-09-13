cmake_minimum_required(VERSION 3.15)
project(tee_fusion C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# -------- Options --------
option(TEE_PLATFORM "tdx|optee|keystone" "tdx")
option(BUILD_SELFTEST "Build selftest_crypto" ON)
option(BUILD_WITH_OPENSSL "Link OpenSSL into tee_fusion if found" ON)

message(STATUS "TEE_PLATFORM = ${TEE_PLATFORM}")

# -------- Includes --------
include_directories(
  include
  core
  core/api
  core/evidence
  core/util
  adapters
)

# -------- Core sources (includes Crypto Addon glue if present) --------
set(CORE_SRCS
  core/api/fusion_api.c
  core/evidence/uevidence_builder.c
  core/evidence/mapping.c
  core/util/cbor_min.c
  core/util/cose_min.c
)

# If crypto_ex.c exists (from OP-TEE Crypto Addon), include it automatically
if(EXISTS "${CMAKE_SOURCE_DIR}/core/api/crypto_ex.c")
  list(APPEND CORE_SRCS core/api/crypto_ex.c)
  message(STATUS "Including Crypto Addon: core/api/crypto_ex.c")
endif()

# -------- Platform adapter selection --------
if(TEE_PLATFORM STREQUAL "tdx")
  set(ADAPTER_SRCS adapters/tdx/adapter_init.c)
elseif(TEE_PLATFORM STREQUAL "optee")
  set(ADAPTER_SRCS adapters/optee/adapter_init.c)
elseif(TEE_PLATFORM STREQUAL "keystone")
  set(ADAPTER_SRCS adapters/keystone/adapter_init.c)
else()
  message(FATAL_ERROR "bad TEE_PLATFORM")
endif()

add_library(tee_fusion STATIC ${CORE_SRCS} ${ADAPTER_SRCS})

# -------- OpenSSL (for examples & helper code) --------
set(OPENSSL_AVAILABLE OFF)
if(BUILD_WITH_OPENSSL)
  # Prefer explicit cross sysroot if provided
  if(DEFINED OPENSSL_ROOT_DIR)
    if(NOT DEFINED OPENSSL_INCLUDE_DIR)
      set(OPENSSL_INCLUDE_DIR "${OPENSSL_ROOT_DIR}/include")
    endif()
    if(NOT DEFINED OPENSSL_SSL_LIBRARY)
      if(EXISTS "${OPENSSL_ROOT_DIR}/lib/libssl.so")
        set(OPENSSL_SSL_LIBRARY "${OPENSSL_ROOT_DIR}/lib/libssl.so")
      elseif(EXISTS "${OPENSSL_ROOT_DIR}/lib/libssl.a")
        set(OPENSSL_SSL_LIBRARY "${OPENSSL_ROOT_DIR}/lib/libssl.a")
      endif()
    endif()
    if(NOT DEFINED OPENSSL_CRYPTO_LIBRARY)
      if(EXISTS "${OPENSSL_ROOT_DIR}/lib/libcrypto.so")
        set(OPENSSL_CRYPTO_LIBRARY "${OPENSSL_ROOT_DIR}/lib/libcrypto.so")
      elseif(EXISTS "${OPENSSL_ROOT_DIR}/lib/libcrypto.a")
        set(OPENSSL_CRYPTO_LIBRARY "${OPENSSL_ROOT_DIR}/lib/libcrypto.a")
      endif()
    endif()
    if(EXISTS "${OPENSSL_INCLUDE_DIR}/openssl/ssl.h" AND EXISTS "${OPENSSL_SSL_LIBRARY}" AND EXISTS "${OPENSSL_CRYPTO_LIBRARY}")
      set(OPENSSL_AVAILABLE ON)
      target_include_directories(tee_fusion PRIVATE "${OPENSSL_INCLUDE_DIR}")
      target_link_libraries(tee_fusion "${OPENSSL_SSL_LIBRARY}" "${OPENSSL_CRYPTO_LIBRARY}")
      target_compile_definitions(tee_fusion PRIVATE HAVE_OPENSSL=1)
    endif()
  endif()

  if(NOT OPENSSL_AVAILABLE)
    find_library(OPENSSL_SSL ssl)
    find_library(OPENSSL_CRYPTO crypto)
    if(NOT OPENSSL_INCLUDE_DIR)
      find_path(OPENSSL_INCLUDE_DIR openssl/ssl.h
        PATHS /usr/include /usr/local/include /usr/include/aarch64-linux-gnu)
    endif()
    if(OPENSSL_SSL AND OPENSSL_CRYPTO)
      set(OPENSSL_AVAILABLE ON)
      target_link_libraries(tee_fusion ${OPENSSL_SSL} ${OPENSSL_CRYPTO})
      target_compile_definitions(tee_fusion PRIVATE HAVE_OPENSSL=1)
    else()
      message(WARNING "OpenSSL not found; examples will be skipped. Install libssl-dev or pass -DOPENSSL_ROOT_DIR=/path/to/aarch64/sysroot/usr.")
    endif()
  endif()
endif()

# -------- OP-TEE client (only when optee) --------
if(TEE_PLATFORM STREQUAL "optee")
  # 优先使用从源码构建导出的 optee_client
  # 传入示例：
  #   -DOPTEE_CLIENT_EXPORT=/abs/path/to/third_party/optee/build/optee_client/out/export/usr
  if(DEFINED OPTEE_CLIENT_EXPORT)
    set(TEEC_EXPORT_INCLUDE "${OPTEE_CLIENT_EXPORT}/include")
    set(TEEC_EXPORT_LIB_SO  "${OPTEE_CLIENT_EXPORT}/lib/libteec.so")
    set(TEEC_EXPORT_LIB_A   "${OPTEE_CLIENT_EXPORT}/lib/libteec.a")
    if(EXISTS "${TEEC_EXPORT_INCLUDE}/tee_client_api.h")
      # 兼容静态/动态两种导出形式
      if(EXISTS "${TEEC_EXPORT_LIB_SO}")
        set(TEEC_EXPORT_LIB "${TEEC_EXPORT_LIB_SO}")
      elseif(EXISTS "${TEEC_EXPORT_LIB_A}")
        set(TEEC_EXPORT_LIB "${TEEC_EXPORT_LIB_A}")
      endif()
    endif()
    if(EXISTS "${TEEC_EXPORT_INCLUDE}/tee_client_api.h" AND EXISTS "${TEEC_EXPORT_LIB}")
      message(STATUS "Using optee_client export: ${OPTEE_CLIENT_EXPORT} (lib: ${TEEC_EXPORT_LIB})")
      target_include_directories(tee_fusion PRIVATE "${TEEC_EXPORT_INCLUDE}")
      target_link_libraries(tee_fusion "${TEEC_EXPORT_LIB}")
      # libteec 依赖 pthread
      find_package(Threads REQUIRED)
      target_link_libraries(tee_fusion Threads::Threads)
    else()
      message(FATAL_ERROR "Invalid OPTEE_CLIENT_EXPORT: ${OPTEE_CLIENT_EXPORT} (missing include or lib)")
    endif()
  else()
    message(WARNING "OPTEE_CLIENT_EXPORT not set; falling back to system paths (libteec-dev).")
    if(NOT TEEC_INCLUDE_DIR)
      find_path(TEEC_INCLUDE_DIR tee_client_api.h
        PATHS /usr/include /usr/local/include /usr/include/aarch64-linux-gnu)
    endif()
    if(NOT TEEC_LIB)
      find_library(TEEC_LIB teec
        PATHS /usr/lib /usr/local/lib /usr/lib/aarch64-linux-gnu)
    endif()
    if(TEEC_INCLUDE_DIR)
      target_include_directories(tee_fusion PRIVATE ${TEEC_INCLUDE_DIR})
    else()
      message(FATAL_ERROR "tee_client_api.h not found. Set -DOPTEE_CLIENT_EXPORT=/path/to/export/usr")
    endif()
    if(TEEC_LIB)
      target_link_libraries(tee_fusion ${TEEC_LIB})
      find_package(Threads REQUIRED)
      target_link_libraries(tee_fusion Threads::Threads)
    else()
      message(FATAL_ERROR "libteec not found. Set -DOPTEE_CLIENT_EXPORT=/path/to/export/usr")
    endif()
  endif()
endif()

# -------- Examples (RA-TLS) --------
if(OPENSSL_AVAILABLE AND EXISTS "${CMAKE_SOURCE_DIR}/examples/ratls/server.c")
  add_executable(ratls_server examples/ratls/server.c)
  target_link_libraries(ratls_server tee_fusion ${OPENSSL_SSL} ${OPENSSL_CRYPTO})
  if(OPENSSL_INCLUDE_DIR)
    target_include_directories(ratls_server PRIVATE "${OPENSSL_INCLUDE_DIR}")
  endif()
  set_target_properties(ratls_server PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()

if(OPENSSL_AVAILABLE AND EXISTS "${CMAKE_SOURCE_DIR}/examples/ratls/client.c")
  add_executable(ratls_client examples/ratls/client.c)
  target_link_libraries(ratls_client tee_fusion ${OPENSSL_SSL} ${OPENSSL_CRYPTO})
  if(OPENSSL_INCLUDE_DIR)
    target_include_directories(ratls_client PRIVATE "${OPENSSL_INCLUDE_DIR}")
  endif()
  set_target_properties(ratls_client PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()

# -------- Selftest (Crypto Addon) --------
if(OPENSSL_AVAILABLE AND BUILD_SELFTEST AND EXISTS "${CMAKE_SOURCE_DIR}/examples/selftest/selftest_crypto.c")
  add_executable(selftest_crypto examples/selftest/selftest_crypto.c)
  target_link_libraries(selftest_crypto tee_fusion ${OPENSSL_SSL} ${OPENSSL_CRYPTO})
  if(OPENSSL_INCLUDE_DIR)
    target_include_directories(selftest_crypto PRIVATE "${OPENSSL_INCLUDE_DIR}")
  endif()
  set_target_properties(selftest_crypto PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()

# -------- Tests --------
enable_testing()
if(EXISTS "${CMAKE_SOURCE_DIR}/tests/CMakeLists.txt")
  add_subdirectory(tests)
endif()

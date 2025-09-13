add_executable(test_cbor tests_cbor.c)
target_link_libraries(test_cbor tee_fusion)
# Keep all runnable outputs under <build>/bin for consistency
set_target_properties(test_cbor PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
add_test(NAME cbor COMMAND test_cbor)

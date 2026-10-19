cmake_minimum_required(VERSION 3.20)

project(AetherbandNative
    VERSION 0.1.0
    DESCRIPTION "Native C++ foundation for Aetherband"
    LANGUAGES CXX
)

option(AETHERBAND_BUILD_TESTS "Build Aetherband native tests" ON)

add_library(aetherband_core
    src/audio_buffer.cpp
    src/mixer.cpp
)

target_include_directories(aetherband_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(aetherband_core PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(aetherband_core PRIVATE /W4 /permissive-)
else()
    target_compile_options(aetherband_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion)
endif()

if(AETHERBAND_BUILD_TESTS)
    enable_testing()
    add_executable(aetherband_core_tests
        tests/audio_buffer_tests.cpp
        tests/mixer_tests.cpp
    )
    target_link_libraries(aetherband_core_tests PRIVATE aetherband_core)
    target_compile_features(aetherband_core_tests PRIVATE cxx_std_20)
    add_test(NAME aetherband_core_tests COMMAND aetherband_core_tests)
endif()

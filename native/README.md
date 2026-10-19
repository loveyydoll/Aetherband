# Native C++/JUCE Target

This directory begins Aetherband's native replacement. JUCE is the committed framework; the current small C++ foundation may remain framework-independent while JUCE integration is added.

## Committed direction

- C++20 or newer, CMake, JUCE.
- Windows and macOS are required.
- Aetherband owns DSP graph execution, processor lifecycle, routing, transport semantics, and offline-rendering rules.
- Rust/Flutter/Dart remain migration references only.

## Current foundation build

Requires CMake 3.20+ and a C++20 compiler.

    cmake -S native -B build/native
    cmake --build build/native --config Debug
    ctest --test-dir build/native --output-on-failure

These commands describe the existing framework-independent foundation and must be verified on the machine where run. They do not yet build a complete JUCE DAW, enumerate devices, or prove hardware playback. Add JUCE setup and platform prerequisites after integration and verification.

## Current limitations

The foundation contains a planar float audio buffer and basic additive mixer with initial tests. It is not yet a usable DAW: device playback/recording, transport, executing DSP graph, media decoding, project persistence, HypnoSynth port, and native arrangement/mixer workflow are not established.

Follow docs/ARCHITECTURE.md, docs/CPP_MIGRATION_PLAN.md, and docs/FEATURE_TRACKER.md.

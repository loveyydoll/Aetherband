# Native C++ Foundation

This directory is the start of the C++ replacement for Aetherband's application and audio runtime. It is deliberately small and framework-independent while the cross-platform desktop/audio framework is evaluated.

## Build and test

Requires CMake 3.20+ and a C++20 compiler.

```sh
cmake -S native -B build/native
cmake --build build/native --config Debug
ctest --test-dir build/native --output-on-failure
```

The current code contains planar float audio buffers and a simple additive mixer. It does **not** yet open an audio device, schedule playback, decode files, or provide a complete DSP graph. Those are separate milestones; this foundation should not be mistaken for a usable DAW yet.

See [the migration plan](../docs/CPP_MIGRATION_PLAN.md) for architecture rules and acceptance criteria.

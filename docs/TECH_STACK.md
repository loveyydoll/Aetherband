# Aetherband Technology Stack — Committed Direction

This document records the target stack. The old Rust/Flutter stack remains in the repository only as a migration reference. Do not use the historical alternatives table or prior implementation notes as current direction.

## 1. Committed stack

| Layer | Decision | Notes |
|---|---|---|
| Primary language | C++20 or newer | Application, runtime, DSP, media, instruments |
| Desktop framework | JUCE | Committed native UI and audio/platform framework |
| Build system | CMake | Reproducible native builds |
| Platforms | Windows and macOS | Both mandatory; verify independently |
| DSP architecture | Aetherband-owned | Own graph execution, processor lifecycle, routing, parameter/automation semantics |
| Audio-device infrastructure | JUCE | Must still validate device behavior and lifecycle on real platforms |
| Session model | Native C++ design, not yet finalized | Versioned, validated, safe save/open |
| Tests | Native unit, offline audio, integration, device tests | Evidence must be recorded per platform |
| License goal | GPL-3.0-or-later | Audit JUCE version/modules and all dependencies for actual obligations |

## 2. Framework and engine boundary

JUCE is the committed framework. Do not reopen selection without an explicit project-owner decision. JUCE provides application/UI, audio-device and platform infrastructure; it does not replace Aetherband's engine semantics or prove callback safety automatically.

Aetherband should own transport behavior, processor lifecycle, graph execution, routing, parameter/automation timing, and deterministic offline rendering. Reuse proven DSP algorithms or infrastructure where licensing, quality, and maintenance justify it.

## 3. Legacy stack

Rust, C ABI/Dart FFI, Flutter, and Dart are retained as references for behavior and migration. Do not add target features to that stack or delete it wholesale before replacements pass acceptance criteria. C#/.NET/Avalonia is not part of the planned core.

## 4. Verification requirements

The current C++ buffer/mixer scaffold is not a complete DAW and has not been verified on both platforms in this migration step. Before calling the stack operational, build and launch a JUCE application on Windows and macOS, enumerate devices, play a known signal, repeat start/stop/close cycles, and record outcomes. Review JUCE's exact version, modules, licence obligations, and packaging implications before release.

See DECISIONS.md, ARCHITECTURE.md, CPP_MIGRATION_PLAN.md, and FEATURE_TRACKER.md.

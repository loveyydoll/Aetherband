# Aetherband Architecture Decision Records

An accepted ADR is binding until a later accepted ADR explicitly supersedes it. Historical decisions remain for context and must not be mistaken for current guidance.

## ADR-001: Desktop-first product

**Status:** Accepted · **Date:** 2026-10-16

Windows and macOS are the required initial desktop targets. Prioritize dense editing, keyboard/mouse workflows, native device behavior, and reliable packaging. Mobile applications are out of scope unless explicitly reconsidered later.

## ADR-002: Rust engine and Flutter UI

**Status:** Superseded by ADR-008 · **Original dates:** 2026-10-16 to 2026-10-17

The earlier architecture used a Rust audio engine and Flutter/Dart UI with a C ABI/Dart FFI boundary. It remains migration-reference material only, not the target stack.

## ADR-003: Real-time thread safety

**Status:** Accepted · **Date:** 2026-10-16

The audio callback must have bounded, predictable work. It must not perform I/O, unpredictable allocation/deallocation, blocking synchronization, or wait for worker/UI threads. Use a bounded command/telemetry strategy with documented overflow behavior. Verify the concrete implementation; no queue is safe merely because it is called lock-free.

## ADR-004: Legacy C ABI and Dart FFI

**Status:** Historical; superseded for target development by ADR-008

The versioned C ABI and Dart FFI belong to the old Rust/Flutter integration. Do not expand them for new target features. Keep only what is required for legacy maintenance and behavioral comparison.

## ADR-005: Legacy Rust audio backend

**Status:** Historical; superseded for target development by ADR-008

The old Rust implementation abstracted device access around CPAL. The C++/JUCE target must define its own device lifecycle and error contracts. Reuse useful behavior, not Rust interfaces or dependencies by default.

## ADR-006: Legacy JSON session format

**Status:** Historical implementation; native format not yet finalized

The old Flutter application has an early-alpha .aetherband.json format with imported audio references and basic track controls. It is not a committed native project format. Audit compatibility needs before selecting the native schema.

## ADR-007: Internal DSP first; plugin hosting later

**Status:** Accepted · **Date:** 2026-10-17

Establish a reliable internal processing graph, instruments, effects, and project workflow before committing to external plugin hosting. Evaluate plugin formats after the core runtime is stable. This does not prohibit reuse of compatible DSP algorithms.

## ADR-008: Native C++ application and JUCE framework

**Status:** Accepted · **Date:** 2026-10-19

**Context:** The project owner has committed to C++ as the foundation and JUCE as the framework.

**Decision:**
1. C++20 or newer is the primary language for the application, runtime, DSP, media systems, and instruments.
2. JUCE is the committed framework for the native desktop UI and audio/platform integration.
3. CMake is the build system.
4. Windows and macOS are mandatory targets.
5. Aetherband owns DSP graph execution, processor lifecycle, routing, parameter/automation behavior, transport semantics, and offline-rendering rules.
6. JUCE is infrastructure, not the engine's identity. Compatible external algorithms and libraries may be used where appropriate.
7. Rust, the old C ABI/Dart FFI, Flutter, and Dart are migration references only. Preserve them until the native replacement passes acceptance criteria; do not delete them wholesale.
8. C# is not part of the planned core. Another language requires a concrete, approved use case.
9. Verify the exact JUCE version, modules, licence obligations, packaging, and dependency compatibility before release.

**Consequences:** New product work targets C++/JUCE. First prove a minimal application builds and launches on both platforms, enumerates devices, plays a known signal, and closes safely. The existing C++ buffer/mixer foundation is not a working DAW.

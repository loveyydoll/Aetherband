# Aetherband — Project State Handoff

**Last reconciled:** 2026-10-19  
**Branch context:** rewrite/cpp-native-foundation, draft migration PR #35  
**Evidence level:** Repository review. The current C++ foundation has not been independently built or run on Windows/macOS in this migration step.

## Product

Aetherband is an early-stage, free/open-source desktop DAW. Its intended creative direction is an expressive arrangement-first workspace combining recording, editing, mixing, instruments, and sound design. Windows and macOS are required targets.

## Binding architecture

- C++20 or newer.
- JUCE is the committed framework, not a candidate.
- CMake build system.
- Aetherband-owned runtime and DSP semantics.
- Windows and macOS required.
- GPL-3.0-or-later is the license goal, subject to dependency compatibility.
- Rust/C ABI/Dart FFI/Flutter/Dart are legacy references only.
- C# is not part of the planned core.

See ADR-008 in DECISIONS.md. Do not reopen framework selection without explicit owner direction.

## C++ foundation present

- CMake/C++20 project scaffold.
- Planar floating-point audio buffer.
- Basic additive mixer.
- Initial unit tests for those primitives.

These are source-level observations, not proof that tests pass or either platform works. A complete JUCE application, device playback, transport, executing DSP graph, media pipeline, project persistence, HypnoSynth port, and usable arrangement/mixer workflow have not yet been established by this foundation slice.

## Migration safety

Do not delete the legacy Rust/Flutter implementation wholesale. Audit actual behavior, then port and test it in small slices. Retire a legacy subsystem only when its C++ replacement passes documented acceptance criteria. Preserve Git history.

## Immediate priorities

1. Integrate JUCE with a documented CMake setup.
2. Build and launch a minimal native app on Windows and macOS.
3. Enumerate devices, play a known signal, and test repeated open/start/stop/close.
4. Define callback-safe runtime contracts and an executing DSP graph.
5. Prove deterministic offline processing.
6. Deliver WAV import → multitrack arrange/play/mix → save/reopen → WAV export.
7. Port HypnoSynth and broaden production features.

## Evidence rules

Code exists is not proof of compilation. Compilation is not proof tests pass. Passing tests is not proof of hardware behavior. Legacy features are not C++ parity. WAV tests do not imply other formats work. A UI prototype is not a complete DAW workflow.

Update this file when architecture decisions or verified platform status change.

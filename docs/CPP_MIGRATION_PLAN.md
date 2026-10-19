# Aetherband C++ Migration Plan

**Status:** Initial migration branch  
**Target platforms:** Windows and macOS  
**Direction:** Native C++ desktop application and audio runtime; Flutter/Dart are no longer the target UI stack.

## Migration rule

This is a clean architectural restart, not a destructive deletion of the current implementation. Keep the Rust/Dart/Flutter implementation available on existing branches and in Git history while the C++ replacement is built and verified. Do not remove the old implementation from the mainline until the replacement has a tested, usable vertical slice and an explicit migration decision.

Port behavior and validated requirements, not Rust source line-for-line. For every subsystem, record what exists, what is tested, what is merely assumed, and what remains to be implemented.

## Proposed boundaries

- **Application model:** project/session state, tracks, clips, commands, undo/redo, serialization.
- **Audio runtime:** device lifecycle, callback, transport, bounded command queues, telemetry, and thread ownership.
- **DSP:** a modular, actually executing processing graph; processors, routing, automation, and parameter changes.
- **Media:** import/decode, resampling, recording, and offline rendering/export.
- **Instruments:** HypnoSynth and future instruments as independent processors.
- **Desktop UI:** native C++ UI framework, selected after a small cross-platform technical spike.
- **Tests:** deterministic unit tests, offline audio tests, serialization compatibility tests, and Windows/macOS build checks.

JUCE is a leading candidate for the desktop/audio-device layer, but framework adoption should be confirmed with a small Windows/macOS build and audio-device prototype before making it a hard dependency. Keep application and DSP interfaces independent of UI widgets.

## Real-time audio requirements

- Never allocate, lock a contended mutex, perform file/network I/O, or destroy complex objects on the audio callback.
- Prepare processors and buffers off the audio thread.
- Transfer commands through bounded, real-time-safe queues.
- Define sample-rate, block-size, channel-layout, and processor-lifecycle contracts.
- Keep offline rendering deterministic and testable independently of hardware.

## Port sequence

1. **Inventory and baseline:** audit Rust modules, public C ABI, tests, session schema, and current feature claims. Mark each feature as implemented, tested, partially implemented, or planned.
2. **C++ foundation:** establish CMake, compiler warnings, cross-platform CI, unit tests, buffer primitives, and a minimal mixer.
3. **Audio proof:** produce a known signal, process it through the DSP path, render it offline, and verify device playback on Windows and macOS.
4. **Session model:** define a versioned project format and tests for save/reopen, tracks, clips, and media references.
5. **Vertical slice:** import WAV, arrange clips, play multiple tracks, use HypnoSynth or a minimal test instrument, mix, save/reopen, and export WAV.
6. **Feature parity:** port recording, supported media formats, mixer controls, effects, MIDI, automation, routing, and undo/redo one tested slice at a time.
7. **Retirement:** remove Flutter/Dart and Rust integration from the active product only after the C++ replacement meets agreed acceptance criteria. Preserve history and archival tags.

## First acceptance criteria

- CMake configures and builds on Windows and macOS.
- CTest runs the native unit tests.
- Audio buffer operations are deterministic and bounds-safe.
- Mixer behavior is tested for multiple inputs and headroom is preserved internally.
- No claim of hardware playback is made until it is actually tested on the target OS and device.

## Existing implementation disposition

The Rust engine is a behavioral reference, not the permanent architecture. Keep it available during migration to compare expected behavior, session semantics, decoding/resampling decisions, and HypnoSynth behavior. Do not assume a feature works merely because its API exists. In particular, distinguish metadata/control graphs from an executing real-time DSP graph and distinguish WAV-only validation from support for other formats.

# Aetherband Roadmap — C++/JUCE

This is an engineering sequence, not a delivery-date promise. A milestone is complete only when its exit criteria have evidence on the current code and relevant platforms.

## Binding direction

C++20+ / JUCE / CMake / Windows and macOS. Aetherband owns DSP/runtime semantics. Rust/C ABI/Flutter/Dart are migration references only. See ADR-008 in DECISIONS.md.

## Stage 0 — Audit and migration map

Inventory the legacy engine, UI workflows, tests, media, sessions, instruments, dependencies, and actual platform evidence. Label behavior verified, implemented-but-unverified, partial, unknown, or planned.

**Exit:** auditable behavior matrix; no parity claims based only on source presence.

## Stage 1 — JUCE platform proof

Integrate JUCE through a reproducible CMake setup. Build and launch a minimal native window on Windows and macOS. Enumerate devices, open/close a stream, play a known test signal, and verify repeated start/stop/close and clean shutdown. Record JUCE version, modules, licence obligations, and platform prerequisites.

**Exit:** builds, launches, device lifecycle, and packaging checks recorded on both platforms.

## Stage 2 — Runtime foundation

Define audio buffers, sample rate, block size, channel layouts, processor lifecycle, transport, bounded command/telemetry flow, device lifecycle, and error handling.

**Exit:** deterministic offline tests pass; callback review finds no I/O, unpredictable allocation, blocking waits, or unsafe processor destruction; device tests pass on both OSes.

## Stage 3 — Executing DSP graph

Implement real processor execution, graph validation, channel layouts, gain/pan, summing/routing, parameter changes, safe graph updates, and offline rendering.

**Exit:** known-signal/golden-output tests cover routing and error paths; invalid graph behavior is safe and documented.

## Stage 4 — First complete DAW slice

Build a native JUCE shell, versioned session model, WAV import, multitrack arrangement/playback, mixer, save/reopen, and stereo WAV export.

**Exit:** import → arrange → play/mix → save → reopen → export succeeds on Windows and macOS with persistence and failure-path tests.

## Stage 5 — Instruments and production

Port HypnoSynth with regression fixtures, then add MIDI/piano roll, recording, effects, routing, automation, undo/redo, and recovery in small slices.

**Exit:** each feature has repeatable tests and known limitations. Test FLAC, MP3, and other formats individually before claiming support.

## Stage 6 — Hardening and ecosystem

Profile realistic sessions, stress test, improve accessibility and keyboard workflows, package both platforms, audit dependencies/licenses, and evaluate plugin/interchange support after the core workflow is dependable.

**Exit:** reproducible builds, published Windows/macOS support matrix, no known critical data-loss/audio-safety defects, and clear release criteria.

## Reporting rules

Source code is not proof of compilation. A build is not proof of audio behavior. Graph metadata is not audio processing. Legacy functionality is not C++ parity. WAV tests do not imply other formats work. Preserve the legacy implementation until the replacement meets acceptance criteria.

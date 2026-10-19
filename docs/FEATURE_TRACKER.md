# Aetherband Feature Tracker

**Reviewed:** 2026-10-19  
**Scope:** Native C++/JUCE target. Legacy behavior is not automatically counted as ported.

## Status vocabulary

- **Verified:** acceptance criteria passed with evidence on the stated platform.
- **Implemented — unverified:** code exists; required tests/runtime/platform behavior has not been established.
- **Prototype:** incomplete demonstration, not a complete workflow.
- **In progress:** active implementation underway.
- **Planned:** not implemented in the target.
- **Legacy reference:** exists in Rust/Flutter/Dart but is not target parity.

## Current architecture

C++20+ / JUCE / CMake; Windows and macOS required; Aetherband owns DSP/runtime semantics. See ADR-008 in DECISIONS.md.

| Area | Target status | Evidence / next action |
|---|---|---|
| CMake C++20 scaffold | Implemented — unverified | Build on Windows and macOS |
| Planar float audio buffer | Implemented — unverified | Run tests and boundary/invalid-input cases |
| Additive mixer | Implemented — unverified | Run tests and deterministic audio cases |
| JUCE application shell | Planned | Integrate JUCE and verify builds/launch on both OSes |
| Device enumeration/lifecycle | Planned | Enumerate, open, play test signal, stop, close, repeat |
| Transport and scheduling | Planned | Define clock and command semantics |
| Real-time command/telemetry flow | Planned | Select bounded mechanism and document overflow/ownership |
| Executing DSP graph | Planned | Process actual buffers; add routing/golden-signal tests |
| Offline rendering | Planned | Deterministic render tests and output validation |
| Session/project model | Planned | Versioned schema, save/reopen, safe failure paths |
| WAV import/background decode | Planned | Test large files, cancellation, errors, and resampling |
| Multitrack arrangement/playback/mix | Planned | End-to-end vertical slice |
| WAV export | Planned | Validate duration, channels, sample rate, and output file |
| HypnoSynth C++ port | Planned | Audit original behavior and create regression fixtures |
| Recording/MIDI/effects/automation/undo-redo | Planned | Deliver after runtime and project model |
| Other audio formats | Planned / unverified | Validate each format independently |
| Plugin hosting/interchange | Deferred | Reconsider after reliable core workflow |

## Immediate priority order

1. JUCE/CMake platform proof.
2. Device lifecycle and known-signal playback.
3. Real-time runtime contracts.
4. Executing DSP graph and offline tests.
5. WAV import → arrange → play/mix → save/reopen → export.
6. HypnoSynth and additional production features.

Update statuses only with relevant test evidence, OS, and limitations. A merge, API declaration, or source file is not evidence of runtime correctness.

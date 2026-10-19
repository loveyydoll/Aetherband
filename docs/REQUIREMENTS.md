# Aetherband System Requirements

**Scope:** Product and engineering requirements for the native C++/JUCE target. Requirements are goals until implemented and verified; this document is not proof of current capability.

## 1. Audio engine and hardware I/O

- **FR-1.1 — Device enumeration and selection:** List available input/output devices and report relevant capabilities where the platform exposes them.
- **FR-1.2 — Stream lifecycle:** Reliably open, start, stop, and close streams without crashes or leaving devices locked.
- **FR-1.3 — Device changes:** Handle device removal or system-default changes safely and communicate failure/recovery to the UI.
- **FR-1.4 — Test signal:** Provide a deterministic internal test signal for pipeline verification.
- **FR-1.5 — File decoding and streaming:** Decode supported formats off the real-time callback and feed playback through a bounded, safe buffering path. WAV is the only format previously reported as tested in the legacy implementation; every other format needs explicit end-to-end tests.
- **FR-1.6 — Multitrack mixing:** Sum multiple tracks to a master output with documented gain and pan laws.
- **FR-1.7 — Recording:** Record input to disk without blocking the audio callback; define failure and recovery behavior.
- **FR-1.8 — Transport:** Define play, stop, seek, loop, and scheduling semantics with predictable timing.

## 2. DSP and instruments

- Implement an executing processor graph, not only graph metadata.
- Define processor prepare/process/release lifecycle, channel layout, parameter changes, automation timing, routing, graph validation, and safe graph replacement.
- Support deterministic offline processing and golden-signal tests.
- Port HypnoSynth only after its behavior and state requirements have been audited.
- External DSP algorithms are allowed when compatible with project licensing and maintenance goals.

## 3. Project/session workflow

- Provide a versioned session model with stable identifiers.
- Import and arrange WAV audio, mix multiple tracks, save and reopen sessions, and export stereo WAV.
- Validate files before replacing the active session.
- Report missing media and failed writes clearly.
- Test round-trip persistence, malformed inputs, missing media, and recovery paths.

## 4. Desktop UI and platform support

- Use C++/JUCE and CMake.
- Windows and macOS are mandatory targets.
- Provide a music-oriented native workspace with arrangement, mixer, transport, menus, keyboard interaction, resizable panels, and high-DPI support.
- Keep UI work off the real-time audio callback.
- Verify build, launch, device lifecycle, and packaging independently on both platforms.

## 5. Real-time and quality requirements

- No blocking I/O, unpredictable allocation/deallocation, contended locks, or unbounded work in the callback.
- Prepare resources off-thread and define safe ownership/teardown.
- Add unit, integration, offline audio, and device lifecycle tests.
- Record exact OS/toolchain/test evidence; do not infer support from source presence.

## 6. Deferred scope

External plugin hosting, advanced project interchange, additional codecs, mobile apps, and cross-language integrations are not prerequisites for the first usable DAW vertical slice. Revisit them after the core workflow is dependable.

See ARCHITECTURE.md, AUDIO_ENGINE.md, CPP_MIGRATION_PLAN.md, and FEATURE_TRACKER.md.

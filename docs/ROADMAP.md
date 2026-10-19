# Aetherband Roadmap — Native C++ Migration

This roadmap describes engineering stages, not delivery-date promises. A milestone is complete only when its exit criteria have evidence on the current commit and the relevant target platforms.

## Architecture direction

- **Core language:** C++20 or newer where supported.
- **Build system:** CMake.
- **Desktop framework:** not yet finalized; JUCE is a leading candidate pending a cross-platform technical spike.
- **Audio runtime and DSP:** native C++ modules, with an Aetherband-owned processing graph and explicit real-time contracts.
- **Platforms:** Windows and macOS.
- **Optional C#:** allowed only when a concrete integration need justifies the additional runtime and interface boundary.
- **Legacy stack:** Rust/C ABI/Flutter/Dart are kept as references during migration, not as the target architecture.

## Stage 1 — Native foundation

**Goal:** establish a small, testable C++ codebase.

Deliver:
- CMake/C++20 project and warnings.
- Buffer primitives and additive mixer.
- Unit tests and CTest integration.
- Windows/macOS build verification.

Exit criteria:
- Both target platforms build from documented steps.
- Native tests pass on both.
- Buffer dimensions and invalid inputs have explicit behavior.

## Stage 2 — Audio runtime

**Goal:** reliable device lifecycle and real-time processing.

Deliver:
- Device enumeration/open/close behind a small interface.
- Callback-owned processing path.
- Transport and bounded command/telemetry flow.
- Clear engine/device lifecycle and error reporting.

Exit criteria:
- Known-signal playback tested on Windows and macOS.
- Repeated open/play/stop/close cycles pass.
- No callback allocation, file I/O or blocking lock in the reviewed processing path.

## Stage 3 — Executing DSP graph

**Goal:** build the processing core that Aetherband can evolve.

Deliver:
- Processor interface and graph validation.
- Gain/pan and summing processors.
- Explicit channel layouts, parameter changes and graph lifecycle.
- Deterministic offline rendering.

Exit criteria:
- Offline golden-signal tests pass.
- Graph connections and channel mismatches fail safely.
- Real-time graph changes follow a documented safe protocol.

## Stage 4 — First useful DAW workflow

**Goal:** create, save and reopen a basic multitrack session.

Deliver:
- Versioned project/session model.
- WAV import and background decode.
- Track/clip scheduling and transport.
- Mixer and offline stereo WAV export.
- Native desktop shell with a basic arrangement.

Exit criteria:
- Import → arrange → play → save → reopen → export works end-to-end.
- Missing media and failed writes are reported safely.
- Session round-trip and audio output are tested.

## Stage 5 — Instruments and production tools

**Goal:** restore and expand proven creative workflows.

Deliver:
- C++ HypnoSynth port with regression fixtures.
- MIDI event model and piano-roll foundations.
- Recording, effects, routing, automation and undo/redo.
- Additional formats only after explicit tests.

Exit criteria:
- Instrument output and state persistence tests pass.
- MIDI timing and automation behavior are tested.
- Recording/export recovery and real hardware behavior are validated.

## Stage 6 — Ecosystem and hardening

**Goal:** prepare a dependable open-source DAW for broader testing.

Deliver:
- Evaluate plugin formats and project interchange.
- Performance profiling with realistic sessions.
- Accessibility, keyboard workflow, preferences and packaging.
- Dependency/license audit and contributor documentation.

Exit criteria:
- Windows/macOS support matrix published.
- Reproducible builds and stress tests.
- No known critical data-loss or audio-safety defects.
- Known limitations and supported workflows documented.

## Rules for reporting progress

- Code presence is not verification.
- A successful build is not proof of audio-device behavior.
- A graph model is not proof of DSP execution.
- WAV tests do not prove support for other media formats.
- A visual prototype is not a functioning workflow.
- Keep the existing Rust implementation until the replacement demonstrates the required behavior; preserve history even after legacy code is retired.

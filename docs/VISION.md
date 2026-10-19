# Product Vision: Aetherband

## Vision

Aetherband is a free and open-source desktop DAW designed around an expressive, arrangement-first creative workspace, reliable native audio, and a processing architecture the project can evolve itself. It should support both focused songwriting and deeper sound design without making creative work feel like operating unrelated tools.

This is a target vision, not a claim that the planned features are currently complete.

## Architecture direction

- **Primary language:** C++20 or newer where supported.
- **Desktop UI:** native C++ framework; JUCE is a leading candidate, subject to a Windows/macOS technical spike.
- **Audio runtime:** C++ modules with explicit real-time thread and device-lifecycle contracts.
- **DSP:** an Aetherband-owned processing graph and processor architecture, with external libraries allowed for well-scoped algorithms or infrastructure.
- **Platforms:** Windows and macOS are required targets.
- **Optional language integrations:** C# may be considered only when a concrete use case justifies the added runtime and interface boundary.

Flutter/Dart are no longer the target UI stack. The existing Rust/Flutter implementation is retained during migration as a behavioral reference; it must not be deleted wholesale before the replacement demonstrates tested parity for the agreed workflows.

## Core principles

1. **Creative continuity:** recording, arrangement, editing, sound design and mixing should form one coherent workflow.
2. **Native reliability:** audio-device behavior, timing, clean shutdown and media handling must be verified on supported systems.
3. **DSP ownership:** Aetherband controls its graph semantics, routing, parameter model and real-time execution. It does not need to reinvent every standard DSP algorithm.
4. **Real-time discipline:** no blocking I/O, allocation or contended locks in the audio callback.
5. **Modular architecture:** UI, project model, media, audio runtime, DSP and instruments have clear contracts and independent tests.
6. **Honest status:** separate planned features, prototypes, implemented code and verified behavior.
7. **Open-source sustainability:** prefer GPL-compatible dependencies, documented trade-offs and reproducible builds.

## Initial migration objective

Build a minimal native vertical slice before expanding the feature set:

1. Build and test the C++ foundation on Windows and macOS.
2. Process a known signal through the DSP path and render deterministic offline audio.
3. Verify audio-device playback and lifecycle behavior.
4. Import WAV, arrange and play multiple tracks, mix, save/reopen a project and export WAV.
5. Port HypnoSynth and other proven behavior in small, tested increments.

See [the C++ migration plan](CPP_MIGRATION_PLAN.md) and [the feature tracker](FEATURE_TRACKER.md) for implementation status and acceptance evidence.

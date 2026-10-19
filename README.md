<div align="center">

<img src="assets/branding/aetherband-primary.svg" alt="Aetherband — official logo" width="470">

<br>

### Make sound your own. Keep the tools open.

**A native, open-source digital audio workstation built around sound, arrangement, and creative control.**

*Early development · Native C++ · JUCE · Windows and macOS*

</div>

---

## Vision

Aetherband is an open-source DAW for people who want to follow musical ideas wherever they lead. It aims to connect recording, arrangement, editing, mixing, synthesis, and sound design in one expressive desktop instrument.

The creative ambition draws on the immediacy of modern arrangement workflows and the depth of established production tools, while developing its own identity. Aetherband should support intimate songwriting, layered and collage-like productions, unusual textures, and ambitious sound design without making the software itself the center of attention.

## Committed technical direction

These are architectural decisions, not suggestions:

- **Language:** C++20 or newer for the application, audio runtime, DSP, media systems, and instruments.
- **Framework:** JUCE is the committed native framework for the desktop application and audio/platform integration.
- **Build:** CMake.
- **Platforms:** Windows and macOS are mandatory targets.
- **Engine ownership:** Aetherband owns DSP graph execution, processor lifecycle, routing, transport semantics, parameter/automation behavior, and offline-rendering rules.
- **Framework role:** JUCE provides infrastructure; it does not define Aetherband's DSP architecture. Proven algorithms and libraries may be reused when quality, licensing, and maintenance make sense.
- **Legacy stack:** Rust, C ABI/Dart FFI, Flutter, and Dart are migration references only. Do not add new product features there unless an explicit maintenance task requires it.
- **C#:** not part of the planned core; another language requires a concrete, approved use case.
- **License goal:** GPL-3.0-or-later, with compatible dependencies and documented distribution obligations.

See docs/ARCHITECTURE.md and docs/DECISIONS.md.

## Honest project status

> [!WARNING]
> **Aetherband is not yet a usable DAW and should not be trusted with important sessions or irreplaceable recordings.** The native C++ migration is at its foundation stage.

The draft migration branch [rewrite/cpp-native-foundation](https://github.com/loveyydoll/Aetherband/tree/rewrite/cpp-native-foundation) starts the replacement. The existing Rust/Flutter implementation is preserved as a behavioral reference until the native target demonstrates the agreed workflows. Do not delete it wholesale.

### Present in the C++ foundation

- CMake-based C++20 project structure.
- Planar floating-point audio-buffer primitive.
- Basic additive mixer.
- Initial unit tests for those primitives.

This is source-level status, not proof that tests pass or that either platform works.

### Not yet established in the C++ target

- A JUCE application shell and verified cross-platform packaging.
- Real device enumeration, playback, recording, and lifecycle.
- Transport and real-time scheduling.
- An executing DSP graph.
- Media decoding, resampling, and offline rendering.
- Project/session persistence and a usable arrangement/mixer workflow.
- HypnoSynth ported to C++.
- End-to-end import → arrange → play/mix → save/reopen → export.

The legacy implementation's features must be audited individually before being called ported. WAV is the only format previously reported as tested; do not assume other formats work.

## Roadmap

1. Prove JUCE builds and launches on Windows and macOS, enumerates devices, plays a known signal, and closes safely.
2. Implement the native audio runtime, transport, and bounded command/telemetry flow.
3. Build an executing DSP graph with deterministic offline tests.
4. Deliver WAV import, multitrack arrangement/playback/mix, save/reopen, and WAV export.
5. Port HypnoSynth with regression tests; then expand MIDI, recording, effects, routing, automation, and undo/redo.
6. Harden performance, accessibility, packaging, licensing, and release workflows.

A milestone is complete only when its acceptance criteria have evidence. See docs/ROADMAP.md and docs/FEATURE_TRACKER.md.

## Building the current foundation

Requires CMake 3.20+ and a C++20 compiler.

    cmake -S native -B build/native
    cmake --build build/native --config Debug
    ctest --test-dir build/native --output-on-failure

These commands describe the current framework-independent foundation. They do not yet launch a DAW or prove JUCE/device behavior. Update the instructions after JUCE integration and verification.

## Engineering principles

- No file/network I/O, unpredictable allocation/deallocation, blocking waits, or contended locks in the audio callback.
- Prepare processors and buffers away from the callback; define ownership and safe teardown.
- Keep UI, session model, media, runtime, DSP, and instruments separated and independently testable.
- Test DSP deterministically offline before relying on hardware tests.
- Port behavior, not source mechanically.
- Distinguish planned, implemented, automated-tested, manually verified, and platform-verified behavior.
- Review third-party licensing against the GPL-3.0-or-later goal.

## Contributing

Start with AGENTS.md, then read docs/AI_WORKFLOW.md, docs/PROJECT_STATE.md, and the relevant architecture documents. Work in small, reviewable changes, add tests, and report exactly what was built and tested. Do not claim Windows/macOS support without testing the relevant platform.

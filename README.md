<div align="center">

<img src="assets/branding/aetherband-primary.svg" alt="Aetherband — official logo" width="470">

<br>

### Make sound your own. Keep the tools open.

**A native, open-source music-making environment built to explore sound.**

*Free and open-source digital audio workstation · Early development*

<br>

[![Status: early development](https://img.shields.io/badge/STATUS-EARLY%20DEVELOPMENT-B567A8?style=flat-square)](#project-status)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/LICENSE-GPL--3.0-655D66?style=flat-square)](LICENSE)
[![Core: C++20](https://img.shields.io/badge/CORE-C%2B%2B20-655D66?style=flat-square)](#technical-direction)
[![Platforms: Windows and macOS](https://img.shields.io/badge/PLATFORMS-WINDOWS%20%7C%20macOS-655D66?style=flat-square)](#platforms)

[Vision](#vision) · [Technical direction](#technical-direction) · [Status](#project-status) · [Roadmap](#roadmap) · [Build](#building-the-native-foundation) · [Contribute](#contributing)

</div>

---

## Vision

**Aetherband is an open-source DAW for people who want to make music, follow ideas wherever they lead, and understand the tools shaping their sound.**

We want the immediacy of capturing a passing idea, the precision to shape a complete production, and a creative environment that welcomes unusual sounds and workflows. Arrangement, recording, editing, mixing, synthesis and sound design should ultimately feel like connected parts of the same instrument.

Aetherband is intended to be free and open-source software. The long-term ambition is a capable DAW with its own instruments and processing technology—not a thin interface over a closed service. This is a direction we are working toward, not a claim that those features already exist.

**Start with a sound. Follow it somewhere new.**

## What we're trying to build

- **An arrangement-first workspace.** Tracks, clips, recording, editing and mixing should form a coherent workflow, from a quick sketch to a complex session.
- **Sound as a creative material.** Instruments, effects, routing, modulation and automation should eventually be first-class parts of the experience.
- **A DSP foundation we can evolve.** We intend to build and own Aetherband's processing architecture while using well-chosen algorithms and libraries where appropriate. Owning the engine does not mean reinventing every standard filter or effect.
- **Native desktop software.** Windows and macOS are the initial targets. Real-time audio behavior and desktop integration take priority over a UI prototype that merely looks complete.
- **Open tools and inspectable decisions.** The code, design choices and limitations should be understandable to musicians and developers alike.

## Project status

> [!WARNING]
> **Aetherband is experimental and is not a usable replacement for a production DAW yet.** The C++ migration has just begun. Do not rely on it for important sessions or irreplaceable recordings.

The existing Rust/Flutter implementation contains useful work and is being kept as a reference during migration. A separate draft migration branch, [`rewrite/cpp-native-foundation`](https://github.com/loveyydoll/Aetherband/tree/rewrite/cpp-native-foundation), starts a new framework-independent C++ foundation. It is not yet a full application and has not yet been verified on Windows or macOS.

### What exists in the new C++ foundation

- A CMake-based C++20 library project.
- A planar floating-point audio buffer primitive.
- A basic additive mixer.
- Initial native unit tests for buffer and mixer behavior.
- A staged migration plan with real-time audio requirements and retirement criteria.

### What is not implemented in the new foundation yet

- Audio-device playback and recording.
- Transport and real-time scheduling.
- An executing DSP graph.
- Media decoding, resampling, and offline rendering.
- HypnoSynth ported to C++.
- Project/session persistence and a native DAW UI.
- Verified Windows and macOS builds or hardware audio tests.

The previous engine's features must be individually audited before we call them ported. Existing Rust code, exported APIs, prototypes, and demo data are not proof of a complete or reliable end-to-end workflow. WAV is the only format previously reported as tested in the earlier implementation; do not assume other formats work until verified.

## Technical direction

### Target architecture

| Area | Direction | Principle |
|---|---|---|
| **Language** | C++20 or newer where supported | A native, testable foundation across Windows and macOS |
| **Desktop UI** | Native C++ UI framework; JUCE is a leading candidate | Validate a minimal cross-platform spike before committing to the framework |
| **Audio runtime** | Aetherband-owned C++ modules | Explicit device lifecycle, transport, callback, thread ownership and bounded command flow |
| **DSP** | Aetherband DSP architecture | Real processing nodes and connections, parameter handling, routing, automation and deterministic offline rendering |
| **Instruments** | Modular native processors, including a future C++ HypnoSynth port | Instruments should integrate through clear processor contracts |
| **Projects** | Versioned session/project model | Stable IDs, safe save/reopen behavior and recoverable media references |
| **Optional integrations** | C# or other languages only when justified | Integrations must have explicit boundaries and must not become unnecessary dependencies of the audio core |
| **Platforms** | Windows and macOS | Both are required targets, not an afterthought |

This is the target direction, not a claim that all these layers have been implemented. The exact UI/audio framework and third-party library choices must be validated against licensing, platform support, build reliability, and actual audio behavior.

### C++ first; optional C# when useful

C++ is the intended foundation for the application and audio runtime. C# is not the primary architecture and should only be introduced if a specific future tool or integration makes it worthwhile. Any such component must have a clear interface and must not compromise real-time audio safety or force the core application to depend on a second runtime without a good reason.

### Build our DSP without reinventing everything

Aetherband should own its processing graph, node lifecycle, routing model, parameter and automation semantics, and real-time execution rules. We can still use established libraries for individual algorithms, device abstractions, file formats or other well-scoped jobs when they fit our open-source goals and license requirements.

The graph must actually process audio. A graph that only stores node and connection metadata is not a functioning DSP engine.

### Real-time audio rules

- Do not allocate memory, perform file I/O, wait on contended locks, or make blocking calls in the audio callback.
- Prepare processors and buffers away from the real-time thread.
- Use bounded, real-time-safe command and telemetry paths.
- Keep UI rendering and project management separate from audio processing.
- Test DSP deterministically offline before relying on hardware playback.
- Measure latency, CPU use, glitches and shutdown behavior rather than assuming they are correct.

## Migration strategy

We are rebuilding the architecture in stages rather than deleting the old implementation in one sweep.

1. **Audit.** Map existing Rust modules and behavior, separating implemented, tested, partially implemented and planned features.
2. **Native foundation.** Establish CMake, compiler warnings, unit tests and Windows/macOS build checks.
3. **Audio proof.** Generate and process known signals, render offline, and verify device playback on both target platforms.
4. **Session model.** Define versioned project state and reliable save/reopen semantics.
5. **First useful vertical slice.** Import WAV, arrange and play multiple tracks, mix, save/reopen, and export WAV; then integrate the instrument port.
6. **Expand deliberately.** Add recording, additional media formats, effects, MIDI, automation, routing, undo/redo and further production workflows with tests.
7. **Retire the legacy stack.** Remove Flutter/Dart and Rust from the active product only after the replacement meets explicit acceptance criteria. Keep Git history and use the old implementation as a behavioral reference during the transition.

## Roadmap

These are engineering stages, not delivery-date promises.

| Stage | Goal | Exit evidence |
|---|---|---|
| **1. Foundation** | CMake/C++20 project, audio buffers, mixer and test harness | Windows/macOS builds and passing native tests |
| **2. Audio runtime** | Device lifecycle, callback, transport and bounded command flow | Repeatable signal/playback tests and clean shutdown on both platforms |
| **3. DSP core** | Executing graph, processor contract, gain/pan and routing | Deterministic offline render tests, graph lifecycle tests and audio-thread safety review |
| **4. Sessions and media** | WAV import, clip scheduling, project save/reopen and WAV export | End-to-end round-trip tests and recoverable error handling |
| **5. Creative core** | HypnoSynth port, MIDI foundations, effects and automation | Processor, timing, state-persistence and regression tests |
| **6. Production workflow** | Recording, mixer, undo/redo, editing and workflow polish | Realistic-session profiling and manual hardware testing |
| **7. Ecosystem and hardening** | Plugin/interchange research, accessibility, packaging and compatibility | Published support matrix, release checklist and no known critical data-loss/audio-safety defects |

No milestone should be called complete solely because code compiles or a pull request merges. Report what has been automated-tested, manually verified on real hardware, implemented but unverified, or left as a prototype.

## Building the native foundation

The new foundation lives in `native/`. It requires CMake 3.20+ and a C++20 compiler.

From the repository root:

```sh
cmake -S native -B build/native
cmake --build build/native --config Debug
ctest --test-dir build/native --output-on-failure
```

These commands are the intended initial workflow; successful execution has not yet been confirmed on both supported operating systems. The current native code is a library and test harness, not a runnable DAW.

For the migration rules and next steps, read [the C++ migration plan](docs/CPP_MIGRATION_PLAN.md). For the older engine's documented state, see [the engine foundation audit](docs/ENGINE_FOUNDATION_AUDIT.md); treat it as a historical source review, not as proof of runtime correctness.

## Project identity

<img src="assets/branding/aetherband-symbol.svg" alt="Aetherband cosmic sound symbol" width="76" align="right">

The Aetherband mark combines a waveform with a cosmic motif: sound as something to discover, reshape and make your own. The [primary logo](assets/branding/aetherband-primary.svg) and [compact symbol](assets/branding/aetherband-symbol.svg) remain part of the project's identity.

## Product principles

- **Make real music workflows possible.** Prioritize coherent, end-to-end functionality over disconnected mock screens.
- **Own the important boundaries.** Keep project state, UI, audio runtime and DSP modules separated by clear contracts.
- **Treat audio safety as a requirement.** Real-time behavior is an architectural constraint, not a late optimization.
- **Never fake success.** Errors, unsupported operations and unverified behavior must be visible.
- **Protect creative work.** Session integrity, source-media handling, recovery and non-destructive editing matter.
- **Build in the open.** Prefer GPL-compatible dependencies, reproducible builds, tests and documented decisions.
- **Show evidence.** Distinguish implemented, tested, manually verified, experimental and planned behavior.

## Contributing

Aetherband welcomes contributors interested in C++ audio engineering, DSP, native desktop UI, cross-platform builds, testing, documentation and music-making workflows.

Before a substantial change:

1. Read [`AGENTS.md`](AGENTS.md), [the project state](docs/PROJECT_STATE.md), [the feature tracker](docs/FEATURE_TRACKER.md), and [the C++ migration plan](docs/CPP_MIGRATION_PLAN.md).
2. Confirm whether the work belongs to the new C++ foundation or is maintenance of the legacy implementation.
3. Make focused changes and add tests for behavior, not just implementation details.
4. Never claim hardware playback or cross-platform support without evidence from the relevant platform.
5. Preserve the legacy code during migration unless a reviewed change explicitly establishes that it is safe to remove.

Please include reproduction steps, operating system, expected behavior and actual behavior in bug reports. Avoid publishing private recordings or sensitive project files.

## Join the experiment

Aetherband is early in its journey. The aim is not to imitate every existing DAW feature immediately, but to build a coherent, open creative instrument on a native foundation that can grow.

**Make sound your own. Keep the tools open.**

[Explore the repository](https://github.com/loveyydoll/Aetherband) · [Report a bug or propose an idea](https://github.com/loveyydoll/Aetherband/issues)

Aetherband is licensed under **GPL-3.0-or-later**.

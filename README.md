<div align="center">

<img src="assets/branding/aetherband-primary.svg" alt="Aetherband — official logo" width="470">

<br>

### Make sound your own. Keep the tools open.

**A creative space for music, experimentation, and the unexpected.**

*Free and open-source digital audio workstation · In development*

<br>

[![Status: early alpha](https://img.shields.io/badge/STATUS-EARLY%20ALPHA-B567A8?style=flat-square)](#where-we-are)
[![License: GPL-3.0](https://img.shields.io/badge/LICENSE-GPL--3.0-655D66?style=flat-square)](LICENSE)
[![Audio engine: Rust](https://img.shields.io/badge/AUDIO-RUST-655D66?style=flat-square)](#under-the-hood)
[![Desktop: Flutter](https://img.shields.io/badge/DESKTOP-FLUTTER-655D66?style=flat-square)](#under-the-hood)

[The idea](#the-idea) · [What we're building](#what-were-building) · [Progress](#where-we-are) · [Roadmap](#roadmap) · [Build](#build-and-verify) · [Contribute](#contributing)

</div>

---

## The idea

**What if a DAW felt less like a set of rules and more like an invitation to make something?**

Some days, you know exactly what you want to record. Other days, you follow a strange sound until it becomes a song. Aetherband is being made for both.

We want to bring together the immediacy of sketching an idea, the freedom to shape a full production, and the openness to understand and extend the tools themselves. Not because every musician needs to write code—but because creative software should leave room for curiosity.

**Start with a sound. Follow it somewhere new.**

This is the direction, not a claim that the finished experience already exists.

## What we're building

<table>
<tr><td width="50%" valign="top">

### Create without losing the idea

An approachable creative workspace, with recording, arranging, editing and mixing designed to work together. The goal is to make getting started feel natural without limiting how far a session can grow.

</td><td width="50%" valign="top">

### Shape sound, not just tracks

We want sound design and experimentation to feel like part of making music, not a separate technical detour. The long-term creative-engine direction explores synthesis, programmable workflows and more expressive ways to work with audio.

</td></tr>
<tr><td valign="top">

### Own your tools

The source is open under GPL-3.0. Our aim is an environment that musicians and developers can inspect, learn from, modify and improve together—not a black box that decides how you must work.

</td><td valign="top">

### Give ideas room to grow

From quick sketches to more involved projects, we want an interface that can become more capable as your work becomes more complex. The long-term research direction also includes spatial-audio foundations.

</td></tr>
</table>

> **These are product goals.** HypnoSynth and basic performance controls are experimental foundations. Windows input recording is implemented, but the physical input path is not yet verified. Editable MIDI, effects, automation, third-party plugins, spatial rendering and full project workflows remain future work.

## Built for curious people

**For musicians:** a place to explore an idea without feeling boxed in by the interface.

**For producers and sound designers:** a long-term vision of deeper control over arrangement, sound and creative workflows.

**For developers:** an open project with a native audio core, a documented boundary to its desktop interface and opportunities to contribute to the instrument itself.

You don't need to be all three. The point is to make room for different ways of creating.

## Where we are

> [!IMPORTANT]
> **Aetherband is in early alpha. It is experimental software, not a production-ready DAW.** Do not trust it with your only copy of important recordings or sessions. Features and plans may change, and there is no announced public release date.

The foundations are taking shape: a Rust audio-engine workspace, native playback/mixing capabilities, a versioned C ABI, and a Flutter desktop application communicating with the engine through Dart FFI. This is real development work, but it is **not** the same as a complete recording-to-export workflow.

**Current target: Windows.** Rust audio playback, imported-track mixing, measured WAV waveforms, and the original HypnoSynth instrument are connected to the Flutter workspace. Local WASAPI and release-DLL integration tests observed nonzero audio samples and clean stream shutdown; speaker/headphone listening and real microphone capture remain unverified.

| Now | Next | Later |
| --- | --- | --- |
| Verify Windows playback and HypnoSynth on real output | Real MIDI editing, clip split/trim/resize and undo/redo | Effects, automation and plugin ecosystem |

For the precise implementation status, read [What works today?](#what-works-today) and the [development roadmap](#roadmap).

## Under the hood

| Layer | Technology | Purpose |
| --- | --- | --- |
| **Audio engine** | Rust | Real-time native audio processing and DSP foundations |
| **Engine interface** | Versioned C ABI | Explicit boundary between audio engine and app |
| **Desktop integration** | Dart FFI | Connects the Flutter UI to the native engine |
| **Desktop experience** | Flutter / Dart | Windows user interface |

The architecture is designed to keep real-time audio processing separate from interface rendering. That design still needs platform testing and ongoing engineering to deliver the intended experience.

**Go deeper:** [Architecture](docs/ARCHITECTURE.md) · [C ABI contract](docs/API_CONTRACT.md) · [Development and release tracking](docs/DEVELOPMENT_AND_RELEASE_TRACKING.md) · [Creative engine & spatial audio direction](docs/CREATIVE_ENGINE_AND_SPATIAL_AUDIO.md)

## A note on the identity

<img src="assets/branding/aetherband-symbol.svg" alt="Aetherband cosmic sound symbol" width="76" align="right">

The Aetherband mark combines a waveform with a cosmic motif: sound as something you can discover, reshape and make your own. The [primary logo](assets/branding/aetherband-primary.svg) and [compact symbol](assets/branding/aetherband-symbol.svg) are available as SVG assets.

---

## What works today?

Aetherband is in an early stage. The distinction between existing code, verified behavior, and planned product features matters.

### Current foundations

- A Rust audio-engine workspace and a C ABI for communication with the desktop UI.
- Native multi-track playback and mixing, master gain, per-track gain/pan/mute/solo, native device sample formats, and full-buffer callback processing.
- HypnoSynth, an original polyphonic software instrument with three original atmospheric and post-punk presets, a live keyboard, performance macros, tempo, metronome, phrase playback and panic.
- Versioned C ABI 0.8.0 and Dart FFI routes for engine, audio, mixer, clip positioning, synth, editable 16-step sequence, Space/R transport shortcuts and session settings, Windows output-device selection, stereo WAV export and Windows input recording.
- Windows is the only current target. Rust signal, transport, callback and FFI tests pass; the opt-in WASAPI callback smoke test passes; Dart analysis passed during implementation.

### Known gaps

- Windows input recording writes a WAV and adds it as a real audio track; its hardware path remains unverified. PCM and IEEE-float WAV clips render measured peaks; other waveform formats are clearly marked unavailable. Editable MIDI, effects, automation, plugin hosting, clip split/trim/resize and undo/redo remain unimplemented. Imported audio clips snap to quarter-note beats when moved while stopped at the start, and their positions persist in session files.
- Local Windows checks pass: 47 Rust core tests, 8 ABI tests, callback-allocation and WASAPI smoke targets, Clippy, release DLL, Flutter analysis, 39 Flutter tests, native FFI integration against the default output device, and a Windows debug build. Remote CI still needs to run on the updated PR head. Physical listening/loopback capture remains unverified.
- Synced `sources/` references and the pre-existing Desktop checkout remain untouched.
- The current CI checks need to pass before the migration can be described as stable.

**Please treat the current build as experimental.** Do not use it as the only copy of important sessions or irreplaceable recordings.

---

## Product principles

- **Explore first.** Make room for experimentation and unexpected workflows.
- **Keep the audio thread safe.** UI work, file I/O, allocation, locks, and blocking calls do not belong in the real-time audio callback.
- **No fake success.** If a native operation is unavailable or fails, report the failure rather than pretending it worked.
- **Make work recoverable.** The intended editing model is non-destructive, with clear ownership of project state and source media.
- **Build in the open.** Prefer transparent decisions, reproducible builds, useful tests, and community discussion.
- **Show the evidence.** Clearly distinguish implemented, automated-tested, manually verified, experimental, and planned behavior.

---

## Roadmap

These are **versioned development milestones**, not delivery-date promises. Alpha 1.0 is not a stable release: it marks the end of the initial alpha roadmap and a transition into broader testing. Beta releases, release candidates, and further testing builds may follow before a separate Stable 1.0. Each milestone should be considered complete only when its exit criteria are met. Scope and sequencing may change as testing and contributor feedback reveal what the project needs.

| Version | Direction | Intended outcome | Exit criteria |
|---|---|---|---|
| **Alpha 0.1 — Connect the Engine** | Stabilize Flutter + native integration | Flutter is the Windows desktop frontend, connected to the Rust engine through the versioned C ABI and Dart FFI. | Windows build, ABI/version and error handling tested; engine lifecycle and clean shutdown verified; Windows CI green. |
| **Alpha 0.2 — Bring Audio In** | Audio import and session basics | Load and remove real audio tracks, show real transport state, and establish a basic session model. | Import/play/pause/stop/remove regression tests; session round-trip tests; failures represented honestly in the UI. |
| **Alpha 0.3 — Shape the Arrangement** | Timeline and waveforms | Work with clips in a visual timeline, with waveform peaks, zoom, scroll, selection, and basic non-destructive edits. | Editing-model tests, large-session profiling, and DPI/layout checks. |
| **Alpha 0.4 — Capture Ideas** | Recording and export | Record from an input and render audio to a usable output file. | Device tests, background disk writing, interruption/error recovery, and export validation. |
| **Alpha 0.5 — Work the Mix** | Mixing workflow | Develop reliable track/master controls, metering, undo/redo foundations, shortcuts, and preferences. | Mixer tests and measured performance with realistic sessions. |
| **Alpha 0.6 — Compose** | MIDI and built-in instruments | Add a MIDI event model, piano roll, MIDI input/recording, and foundations for native instruments and drums. | MIDI editing/playback tests, timing checks, and deterministic project persistence. |
| **Alpha 0.7 — Shape Sound** | Effects and automation | Add native effects, parameter automation, and a researched plugin-hosting prototype. | DSP correctness, automation timing tests, and a documented fault-isolation plan before third-party plugin support. |
| **Alpha 0.8 — Open the Ecosystem** | Plugin and project interchange | Evaluate CLAP first, assess VST3 feasibility and licensing, and investigate project interchange. | Compatibility matrix, plugin validation, crash-containment strategy, and reproducible project tests. |
| **Alpha 0.9 — Make It Dependable** | Performance and release readiness | Improve CPU/memory behavior, accessibility, keyboard workflow, packaging, documentation, and compatibility. | Stress tests, release checklist for supported systems, issue triage, and no known critical data-loss or audio-safety defects. |
| **Alpha 1.0 — Testing Baseline** | Complete the initial alpha roadmap and prepare for wider testing | Establish a coherent baseline for testing supported workflows; this is not a stable or production-ready release. | Core supported workflows are documented; known limitations and data risks are published; test builds can be reproduced; no placeholders are presented as finished features. |


### After Alpha 1.0

Alpha 1.0 does **not** mean Aetherband is stable. Development can continue through multiple testing stages, and version numbers alone do not guarantee reliability.

- **Beta releases** — broaden testing of implemented workflows, usability, compatibility, performance, and bug fixes.
- **Release candidates (RCs)** — validate a specific proposed release against published release criteria.
- **Stable 1.0** — a separate milestone, reached only when the supported workflows meet documented quality, reliability, compatibility, and data-integrity requirements.

The number and duration of beta, RC, and other testing releases will depend on findings from real use and testing. No fixed schedule is implied.

---

## Architecture

Aetherband separates the creative interface from the work that must run close to the audio hardware.

| Technology | Role | Current status |
|---|---|---|
| **Rust** | Native audio engine, decoding, mixing, DSP and real-time callback | Core implementation exists; correctness and platform behavior still require regression testing |
| **C ABI** | Versioned boundary between native engine and desktop UI | ABI 0.8.0; includes audio, mixer, clip positions, transport, editable HypnoSynth sequence, device selection, stereo export, and Windows input recording; see [API_CONTRACT.md](docs/API_CONTRACT.md) |
| **Dart FFI** | Native library loading, ABI validation, engine lifecycle and telemetry | Windows worker-isolate path connects audio and performance controls |
| **Flutter / Dart** | Windows desktop UI and creative workspace | Main interface; the initial session opens empty with HypnoSynth ready |
| **CPAL / Symphonia / rtrb** | Audio device I/O, media decoding and bounded cross-thread communication | Used by the Rust engine; exact supported formats and runtime behavior must be verified per platform |

### Why Flutter?

Flutter gives Aetherband control over a highly customized Windows interface. Its rendering and iteration model offer useful opportunities for custom timeline and editor work.

Flutter is **not automatically faster** than other UI frameworks. Large arrangements, waveform rendering, meters, memory use, accessibility, and platform behavior must be measured and tested. The current target is Windows only; platform work will be reconsidered after its audio and session workflows are dependable.

### Why keep audio in Rust?

The audio engine must remain independent of UI rendering and Dart garbage collection. Real-time callbacks must not perform UI work, file I/O, allocation, or blocking FFI operations. UI commands and telemetry cross the ABI; continuous audio processing stays in the native engine.

### Trade-offs we accept

- Dart FFI adds ABI, ownership, and lifecycle complexity. Keep declarations reviewed, versioned, and tested against the actual C ABI.
- Native libraries must be built and packaged for each supported platform and architecture.
- Desktop polish is work: keyboard shortcuts, accessibility, scaling, file dialogs, window behavior, and clean shutdown require platform-specific verification.
- Rendering performance must be profiled with realistic sessions; virtualization and bounded UI work may be necessary.
- Migrating the frontend costs time and can temporarily leave feature gaps. The Flutter frontend is the intended desktop target; feature parity must be earned through implementation and tests.

---

## Build and verify

The commands below are starting points for local development; successful execution depends on having the required Rust and Flutter toolchains installed and the native library available for the host platform.

### Rust engine and C ABI

From the repository root:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo build -p daw_core_ffi
```

### Flutter desktop

From `apps/desktop/` (the current path; the directory name is legacy and does not make Flutter a secondary UI):

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Windows is the only supported development target for this work. Other platforms are deferred.

**Before reporting a feature as working**, test the relevant path end to end. A successful compile alone does not prove that audio playback, recording, device changes, or shutdown behaves correctly on real hardware.

---

## Contributing

Aetherband is for musicians who want to shape their tools and developers who want to help build them.

- Read the architecture and current milestone before starting a large change.
- Prefer focused pull requests with a clear purpose and tests.
- Do not change real-time audio behavior without considering callback safety and regression coverage.
- Keep illustrative/demo content clearly distinguished from real session and engine state. Flutter is the primary desktop UI.
- Include reproduction steps for bugs, especially for device, transport, and shutdown issues.
- Discuss substantial architectural or product changes before investing in a large implementation.

Useful contributions include Rust audio engineering, Flutter interaction design, Windows testing, accessibility, documentation, and feedback from real music-making workflows.

Bug reports and thoughtful feature discussions are welcome. Please include your operating system, steps to reproduce, expected behavior, and actual behavior. Do not attach private recordings or sensitive project files unless you are comfortable sharing them publicly.

---

## Join the experiment

Aetherband is not finished—and it is not trying to pretend otherwise. It is an open effort to explore what a creative audio workspace can become when musicians and developers can both look inside and help shape it.

**Make sound your own. Keep the tools open.**

[Explore the repository](https://github.com/loveyydoll/Aetherband) · [Report a bug or propose an idea](https://github.com/loveyydoll/Aetherband/issues)

Aetherband is licensed under **GPL-3.0**. Contributions are welcome.

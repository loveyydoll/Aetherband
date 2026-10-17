<div align="center">

<img src="assets/branding/aetherband-primary.svg" alt="Aetherband primary logo" width="520">

# Aetherband

</div>

> **Make sound your own. Keep the tools open.**

Aetherband is an experimental, free and open-source digital audio workstation built for people who want room to explore—not just another closed box for making music. The long-term vision is an open creative platform where recording, arranging, sound design, and mixing can grow together, with a distinctive workspace and an audio engine that stays open to inspection and contribution.

**Status: early alpha · actively evolving · not yet recommended for production sessions**

Aetherband is being built in the open. Expect incomplete workflows, changing interfaces, and breaking changes while the foundations take shape. We will distinguish what exists from what we want to build; planned features are not promises of a release date.

- **Vision:** a flexible creative workspace for musicians, producers, sound explorers, and the people who build audio tools.
- **License:** GPL-3.0
- **Architecture:** Rust audio engine · versioned C ABI · Dart FFI · Flutter desktop UI
- **Current focus:** make the Flutter desktop application a reliable primary UI by stabilizing its Rust-engine connection, removing misleading controls, and verifying end-to-end workflows.

> A note on the vision: Aetherband aims to become a capable DAW. It is not yet a replacement for established production software, and the features in the roadmap below should be read as goals—not as functionality that is already available.

---

## Visual identity

The primary Aetherband logo is stored as an editable, scalable SVG at [`assets/branding/aetherband-primary.svg`](assets/branding/aetherband-primary.svg). It is the original artwork designed in Figma, not a generated approximation. Use the logo on dark or light backgrounds with sufficient contrast; the symbol and wordmark should remain legible at smaller sizes. The visual identity is evolving alongside the project.

## Why Aetherband?

Creative tools shape how we think. We want Aetherband to become a place where the interface can adapt to the work, where the internals are not a black box, and where musicians and developers can influence the instrument they are building together.

### An open creative platform

Aetherband is intended to be more than a list of DAW features. The project aims to make its architecture, development decisions, and future direction visible, so people can learn from it, contribute to it, and eventually shape their own workflows around it.

### A workspace with its own character

The Flutter frontend is Aetherband’s **primary desktop UI**, not a separate experimental alternative to another frontend. It provides the foundation for custom timeline lanes, clip interactions, meters, editors, and instrument panels. The UI is still early alpha: the application architecture is the chosen direction, while many DAW workflows remain incomplete.

## Long-term creative engine direction

Aetherband's longer-term direction includes an extensible synthesis environment, visual programming, and spatial-audio foundations. The architecture and staged delivery plan are documented in [Creative Engine and Spatial Audio Direction](docs/CREATIVE_ENGINE_AND_SPATIAL_AUDIO.md). These are planned capabilities; spatial rendering, immersive delivery, and programmable DSP are not currently complete features.

## Architecture and contributor documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Actual C ABI contract](docs/API_CONTRACT.md)
- [Development and release tracking](docs/DEVELOPMENT_AND_RELEASE_TRACKING.md)
- [Creative engine and spatial-audio direction](docs/CREATIVE_ENGINE_AND_SPATIAL_AUDIO.md)

## Development roadmap

The audio engine is written in Rust. The long-term architecture keeps real-time audio work in the native engine and separates it from the Flutter presentation layer. That boundary makes the system easier to reason about, test, and evolve.

### Open by design

The project is licensed under GPL-3.0. We want contributors to be able to inspect the implementation, reproduce builds, discuss trade-offs, and help decide what Aetherband becomes. No proprietary lock-in is part of the vision.

---

## What works today?

Aetherband is in an early stage. The distinction between existing code, verified behavior, and planned product features matters.

### Current foundations

- A Rust audio-engine workspace and a C ABI for communication with the desktop UI.
- Native engine functionality for multi-track playback and mixing.
- C ABI exports for engine lifecycle, transport, telemetry, audio-device operations, test tone, and track controls. Not every exported operation is yet connected to a complete user-facing workflow.
- The primary Flutter desktop application with Dart FFI integration for engine lifecycle, ABI-version validation, transport, sample-rate query, and telemetry; full DAW feature parity is not yet complete.
- Regression coverage for the **Stop/rewind transport fix**. The Flutter migration does not intentionally change that transport implementation.

### Known gaps

- The Flutter application is the main desktop UI, but the current workspace is still early alpha: demo tracks/clips are not evidence of a loaded or saved session. The directory name `apps/desktop/` is legacy organization, not a statement that Flutter is a disposable or secondary frontend.
- Device selection, audio import, track management, and transport behavior still need end-to-end verification on supported desktop platforms.
- Recording, MIDI editing, built-in instruments, effects, automation, third-party plugin hosting, project save/load, and export must not be considered complete unless they are implemented and tested.
- Windows and macOS native-library packaging, playback, and clean shutdown need repeatable verification.
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
| **Alpha 0.1 — Connect the Engine** | Stabilize Flutter + native integration | Flutter is the desktop frontend, connected to the Rust engine through the versioned C ABI and Dart FFI. | Windows and macOS builds verified; ABI/version and error handling tested; engine lifecycle and clean shutdown verified; CI green. |
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
| **C ABI** | Versioned boundary between native engine and desktop UI | ABI 0.2.0; includes a sample-rate query; exported functions are documented in [API_CONTRACT.md](docs/API_CONTRACT.md) |
| **Dart FFI** | Native library loading, ABI validation, engine lifecycle and telemetry | Initial lifecycle/transport/telemetry path implemented; device and track workflows remain incomplete |
| **Flutter / Dart** | Windows/macOS primary desktop UI and creative workspace | Chosen sole desktop frontend; demo clips remain illustrative and several menu actions are not implemented |
| **CPAL / Symphonia / rtrb** | Audio device I/O, media decoding and bounded cross-thread communication | Used by the Rust engine; exact supported formats and runtime behavior must be verified per platform |

### Why Flutter?

Flutter gives Aetherband control over a highly customized interface and a shared Windows/macOS presentation layer. Its rendering and iteration model offer useful opportunities for custom timeline and editor work.

Flutter is **not automatically faster** than other UI frameworks. Large arrangements, waveform rendering, meters, memory use, accessibility, and platform behavior must be measured and tested. The reason for choosing Flutter is the balance of interface flexibility, rapid visual iteration, cross-platform UI development, and a clear boundary around the native engine—not a blanket performance claim.

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

Use `flutter run -d macos` on macOS. Build the native engine library for the host platform and make it available at the location expected by the FFI adapter.

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

Useful contributions include Rust audio engineering, Flutter interaction design, testing on Windows and macOS, accessibility, documentation, and feedback from real music-making workflows.

Bug reports and thoughtful feature discussions are welcome. Please include your operating system, steps to reproduce, expected behavior, and actual behavior. Do not attach private recordings or sensitive project files unless you are comfortable sharing them publicly.

---

## Join the experiment

Aetherband is not finished—and it is not trying to pretend otherwise. It is an open effort to explore what a creative audio workspace can become when musicians and developers can both look inside and help shape it.

**Make sound your own. Keep the tools open.**

[Explore the repository](https://github.com/loveyydoll/Aetherband) · [Report a bug or propose an idea](https://github.com/loveyydoll/Aetherband/issues)

Aetherband is licensed under **GPL-3.0**. Contributions are welcome.

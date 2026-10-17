# 🌌 Aetherband

> **A free, open-source desktop Digital Audio Workstation focused on expressive workflow, visual flexibility, and dependable real-time audio.**

Aetherband combines an arrangement-first creative workspace with a native Rust audio engine. It is early-alpha software: features, APIs, and project formats may change, and it is not yet recommended for production sessions.

## Product direction: Flutter + Dart FFI

**The desktop frontend is migrating to Flutter/Dart. Avalonia is no longer the target UI and is being removed from the application architecture.** Flutter is the product UI; Rust remains responsible for audio I/O, decoding, mixing, DSP, and real-time work. Flutter communicates with the engine only through the versioned C ABI in `bindings/c_abi/` using Dart FFI.

### Why move to Flutter?

| Advantage | Why it matters for Aetherband |
|---|---|
| **UI flexibility** | Custom timeline lanes, clip rendering, mixer surfaces, meters, editors, and instrument panels can be composed and painted with fine-grained control instead of adapting every interaction to a conventional desktop-widget toolkit. |
| **Rendering consistency** | Flutter's retained widget model and Skia/Impeller rendering path give the project more control over a consistent visual language across Windows and macOS. Actual frame-time and GPU performance must still be profiled. |
| **Optimization opportunities** | Timeline painting, waveform/peak rendering, virtualization of large track lists, and custom hit-testing can be tuned for a DAW-specific workload. Flutter does not automatically make the app faster; profiling and bounded work are required. |
| **Productive iteration** | Hot reload and a declarative UI make rapid experimentation with arrangement layouts, interaction patterns, and visual design easier. |
| **Cross-platform desktop UI** | One Dart/Flutter presentation layer can target Windows and macOS while the same Rust engine and C ABI remain native. |
| **Clear engine boundary** | Dart FFI encourages an explicit, auditable boundary: UI/control data crosses the ABI, while continuous audio buffers and DSP stay in Rust. |
| **Design-system ownership** | Aetherband can build a distinctive, cohesive workstation interface instead of being limited by the defaults and conventions of a general-purpose desktop UI framework. |
| **Future contributor reach** | Dart/Flutter is a widely used UI stack with a substantial ecosystem, potentially lowering the barrier for contributors interested in frontend work. |

### Trade-offs and risks

| Cost / risk | Mitigation |
|---|---|
| **A second language and FFI complexity** | Keep the C ABI small, versioned, documented, and tested; isolate all native calls in one Dart adapter. |
| **Native library packaging** | Build and bundle the correct Rust dynamic library for each supported OS/architecture, and fail clearly when it is missing or the API version is incompatible. |
| **Lifecycle and concurrency hazards** | Serialize calls for each engine handle; never destroy the engine while calls are in flight. Do not block the UI isolate on long operations. |
| **Desktop polish is not free** | Explicitly test keyboard shortcuts, accessibility, DPI scaling, window resizing, file dialogs, and platform conventions on Windows and macOS. |
| **Rendering performance must be proven** | Profile realistic sessions with many tracks and clips; virtualize off-screen content and avoid rebuilding/painting the entire timeline on every meter tick. |
| **Migration cost and temporary feature gaps** | Treat the Flutter app as the only desktop frontend target, but track each native workflow and test it before declaring parity. Do not claim a mock or disabled action works. |
| **Dart FFI is not a generated high-level SDK** | Maintain handwritten, reviewed FFI declarations that match the actual `#[repr(C)]` ABI, with layout/version tests and explicit ownership rules. |

### Decision

The change is primarily motivated by **greater UI flexibility and control over rendering/optimization**, plus faster visual iteration, a consistent Windows/macOS frontend, and a clearer long-term boundary between UI and the native engine. This is a product/engineering trade-off, not a claim that Flutter inherently outperforms Avalonia in every workload. The audio engine remains Rust so UI rendering and garbage collection do not enter the real-time audio callback.

## Current capabilities and limitations

### Native engine foundations
- Rust audio engine and C ABI.
- Audio-device enumeration/selection, transport, master volume, test tone, track loading/removal, track gain/pan/mute, and telemetry exports exist in the C ABI.
- Multi-track playback and mixing are implemented in the Rust core.
- The maintainer reports the Stop/rewind bug is fixed, including regression coverage. This migration does not alter that transport implementation.

### Flutter desktop frontend
- The Flutter workspace currently contains the arrangement-first visual prototype and UI tests.
- The C ABI exists, but the production-quality Dart FFI adapter, native library packaging, and end-to-end Flutter audio workflows must be verified before calling the migration complete.
- Demo clips, instruments, recording state, and any unconnected menu actions are not real audio features unless explicitly wired to the native engine.
- Project save/load, recording, MIDI, plugin hosting, automation, and export are not to be considered complete unless implementation and tests demonstrate them.

## Development roadmap

The roadmap uses **versioned alpha milestones** rather than broad phases. Version labels describe intended delivery gates, not a promise that a feature already works.

| Version | Goal | Planned deliverables | Exit gate |
|---|---|---|---|
| **Alpha 0.1 — Flutter Engine Connection** | Make Flutter the actual desktop app | Dart FFI adapter; API-version/error handling; native library loading; engine create/destroy lifecycle; transport, test tone, device list, telemetry; remove Avalonia frontend and .NET UI workflow | Flutter builds on Windows and macOS; ABI smoke tests pass; no simulated success for native operations; clean shutdown verified |
| **Alpha 0.2 — Audio Import & Session Basics** | Create a useful first session | File picker; load/remove audio tracks; track list and real transport state; basic project/session schema; explicit missing-file/error UI | Load/play/pause/stop/remove regression tests; session round-trip tests; no false UI state |
| **Alpha 0.3 — Arrangement & Waveforms** | Make editing visual and responsive | Real peak generation/cache; waveform display; zoom/scroll; clip selection and non-destructive move/split; timeline virtualization | Large-session UI profiling, DPI/layout tests, and edit-model tests |
| **Alpha 0.4 — Recording & Export** | Capture and render audio | Audio input selection; recording pipeline with background disk writing; safe take management; offline WAV export | Input/output-device tests, interruption/error recovery, export comparison tests |
| **Alpha 0.5 — Mixing Workflow** | Build a dependable mixer | Track/master controls, metering, buses/sends where supported, undo/redo foundation, keyboard shortcuts, preferences | Automated mixer tests and measured performance with realistic sessions |
| **Alpha 0.6 — MIDI & Built-in Instruments** | Add composition tools | MIDI event model, piano roll, MIDI input/recording, native instruments and drum/sampler foundations | MIDI editing/playback tests, timing checks, deterministic project persistence |
| **Alpha 0.7 — Effects & Automation** | Expand sound shaping | Native effects, parameter automation, plugin-hosting research/prototype, preset handling | DSP correctness, automation timing, crash isolation plan before third-party plugins |
| **Alpha 0.8 — Plugin Hosting & Interchange** | Evaluate ecosystem compatibility | CLAP first evaluation, VST3 feasibility/legal review, plugin scan/validation and fault containment; project interchange | Plugin compatibility matrix, sandbox/crash strategy, reproducible project tests |
| **Alpha 0.9 — Performance & Release Candidate** | Stabilize before 1.0 | CPU/memory profiling, accessibility, keyboard workflow, installer/signing, migration/docs, format compatibility | Windows/macOS release checklist, stress tests, issue triage and no known critical data-loss/audio-safety bugs |
| **1.0 — Stable Desktop DAW** | Reliable public release | Supported workflows documented, stable project format policy, installer/update guidance, contributor docs | All release gates met on supported OS versions; no placeholder features presented as finished |

## Build and verify

### Rust engine and C ABI
From the repository root:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo build -p daw_core_ffi
```

### Flutter desktop
From `prototypes/aetherband-flutter-ui/`:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Use `flutter run -d macos` on macOS. The native engine library must be built for the host platform and available at the path documented by the FFI adapter.

## Principles

- **The audio thread is sacred:** no UI framework, Dart isolate, allocation, file I/O, lock, or blocking FFI call belongs in the real-time callback.
- **No fake success:** an unavailable native function or missing library must be reported, not simulated as successful audio.
- **Evidence over checkboxes:** distinguish implemented, automated-tested, manually verified, and planned work.
- **Non-destructive editing:** preserve source audio and make project state recoverable.
- **Open source by design:** transparent architecture, reproducible builds, and no telemetry or proprietary lock-in.

Aetherband is licensed under GPLv3. Contributions and issue reports are welcome.

# Architecture Decision Records (ADRs): Aetherband

## Index of Decisions

- [ADR-001: Desktop-First Architecture with Decoupled Mobile Companion](#adr-001-desktop-first-architecture-with-decoupled-mobile-companion)
- [ADR-002: Rust Audio/DSP Core with C# / Avalonia Desktop Frontend](#adr-002-rust-audiodsp-core-with-c--avalonia-desktop-frontend)
- [ADR-003: Lock-Free SPSC Ring Buffers for Audio Thread Synchronization](#adr-003-lock-free-spsc-ring-buffers-for-audio-thread-synchronization)
- [ADR-004: Flat C-ABI with csbindgen for Type-Safe Interoperability](#adr-004-flat-c-abi-with-csbindgen-for-type-safe-interoperability)
- [ADR-005: Encapsulated AudioBackend Trait over Direct cpal Coupling](#adr-005-encapsulated-audiobackend-trait-over-direct-cpal-coupling)
- [ADR-006: Bundled Zip Container (.dawproject) for Project Files](#adr-006-bundled-zip-container-dawproject-for-project-files)
- [ADR-007: High-Quality Internal DSP First; Defer External Plugin Hosting](#adr-007-high-quality-internal-dsp-first-defer-external-plugin-hosting)
- [ADR-008: Flutter Desktop UI via the Existing C ABI](#adr-008-flutter-desktop-ui-via-the-existing-c-abi)

---

### ADR-001: Desktop-First Architecture with Decoupled Mobile Companion
- **Status:** Approved
- **Date:** 2026-10-16
- **Context:**
  The project vision encompasses desktop platforms (Windows, macOS) and mobile/touch platforms (iOS, iPadOS, Android). Building a single UI to serve both paradigms creates ergonomic compromises: desktop users need high information density, multi-window support, and precision mouse editing, while mobile users need large touch targets and simplified single-window workflows. Additionally, developing iOS on Windows requires remote macOS build agents.
- **Decision:**
  Develop Aetherband as a dedicated desktop-first flagship application for Windows and macOS. The audio engine (`daw_core`) and project format (`.dawproject`) remain 100% platform-agnostic. A separate mobile companion DAW for iOS/iPadOS and Android will be developed later, reusing the proven Rust core.
- **Consequences:**
  - Dramatically accelerates desktop development; eliminates iOS build overhead from Windows.
  - Allows the desktop UI to be optimized specifically for keyboard/mouse without touch compromises.
  - Guarantees seamless project sharing when the mobile app is built.

---

### ADR-002: Rust Audio/DSP Core with C# / Avalonia Desktop Frontend
- **Status:** Superseded for frontend direction by ADR-008; retained as historical record of the original implementation
- **Date:** 2026-10-16
- **Context:**
  Real-time audio requires deterministic execution without garbage-collection pauses. C# is the developer's strongest language, but managed runtimes are prone to GC pauses during low-latency audio callbacks. C++ is the legacy audio standard but is prone to memory safety bugs and complex build toolchains.
- **Decision:**
  Implement the audio engine, DSP algorithms, mixer, and device I/O in pure Rust. Implement the desktop application and UI in C# using Avalonia UI (v11+).
- **Consequences:**
  - Audio thread achieves hard real-time safety with zero garbage collection.
  - Developer productivity is maximized in C# for complex desktop UI layouts.
  - Requires maintaining a clean FFI boundary between Rust and C#.

---

### ADR-003: Lock-Free SPSC Ring Buffers for Audio Thread Synchronization
- **Status:** Approved
- **Date:** 2026-10-16
- **Context:**
  The UI thread and audio thread must exchange commands (Play, Stop, Gain changes) and telemetry (metering, playhead positions). Using standard OS mutexes (`std::sync::Mutex`) risks priority inversion, leading to audio dropouts (xruns).
- **Decision:**
  Use wait-free Single-Producer Single-Consumer (SPSC) ring buffers (`rtrb` crate) for all cross-thread communication. The audio callback never acquires a lock or waits on a worker thread.
- **Consequences:**
  - Guaranteed real-time audio thread execution.
  - Commands and telemetry must be structured as fixed-size value types.
  - Telemetry is lossy (old frames dropped if UI is sluggish), which is acceptable for meters.

---

### ADR-004: Flat C-ABI with csbindgen for Type-Safe Interoperability
- **Status:** Approved
- **Date:** 2026-10-16
- **Context:**
  Hand-written P/Invoke declarations in C# frequently suffer from data alignment mismatches, typos, and synchronization drift when Rust structs change.
- **Decision:**
  Expose the Rust core via a flat C99 ABI (`extern "C"`) and generate C# P/Invoke bindings automatically using `csbindgen`.
- **Consequences:**
  - 100% compile-time verified memory layout between C# and Rust.
  - Eliminates manual FFI glue maintenance.
  - Clean separation: C# never interacts with internal Rust structs directly, only with the C-ABI facade.

---

### ADR-005: Encapsulated AudioBackend Trait over Direct cpal Coupling
- **Status:** Approved
- **Date:** 2026-10-16
- **Context:**
  `cpal` is a low-level cross-platform audio stream wrapper, but professional audio interfaces on Windows often require ASIO for sub-5ms latency. Direct coupling to `cpal` would make swapping backends difficult.
- **Decision:**
  Abstract device management and stream callbacks behind an internal `AudioBackend` trait in Rust. Provide `CpalBackend` as the primary implementation, leaving a clean integration point for an optional `AsioBackend`.
- **Consequences:**
  - Engine logic is fully decoupled from the audio driver library.
  - Headless unit testing can use a `DummyAudioBackend` to simulate hardware callbacks at arbitrary speeds without real sound cards.

---

### ADR-006: Bundled Zip Container (.dawproject) for Project Files
- **Status:** Approved
- **Date:** 2026-10-16
- **Context:**
  Musicians frequently encounter "missing audio file" errors when moving project files between computers because audio files were linked via absolute filesystem paths.
- **Decision:**
  Package project files as standard ZIP archives (`.dawproject`) containing `project.json` for timeline metadata and an `assets/` directory containing all recorded and imported audio files.
- **Consequences:**
  - Projects are 100% self-contained and effortlessly shared.
  - Standard ZIP compression saves disk space for project metadata.
  - Can be inspected or recovered using standard archive tools.

---

### ADR-007: High-Quality Internal DSP First; Defer External Plugin Hosting
- **Status:** Approved
- **Date:** 2026-10-16
- **Context:**
  Third-party plugin hosting (VST3, AU) introduces severe complexity: out-of-process sandboxing, Steinberg SDK licensing, unstable third-party GUI windows, and unexpected plugin crashes.
- **Decision:**
  Focus initial phases on rock-solid internal DSP: subtractive synthesizer, drum sampler, parametric EQ, compressor, delay, and reverb. Defer third-party plugin hosting to Phase 5, adopting the open **CLAP** standard first, followed by VST3.
- **Consequences:**
  - Guarantees immediate host stability and zero licensing hurdles for the MVP.
  - Users get a complete, functional out-of-the-box production experience without requiring paid plugins.
\n\n### ADR-008: Flutter Desktop UI via the Existing C ABI

- **Status:** Approved by project owner
- **Date:** 2026-10-17

**Context:** Aetherband's first audio-connected desktop interface is C#/.NET + Avalonia. The project owner has explicitly selected Flutter as the long-term desktop UI and requires the Flutter implementation to reach full DAW scope. Abandoning it because the first implementation is a prototype or because integration is difficult is not an accepted default.

**Decision:**
- Implement the primary Windows/macOS desktop frontend in Flutter/Dart at full scale.
- Integrate to the existing Rust engine exclusively through the flat C ABI in `bindings/c_abi/src/lib.rs`, using a dedicated Dart FFI adapter.
- Keep the Rust engine and real-time audio path in Rust. Do not rewrite DSP/decoding/device callbacks in Dart.
- Keep C#/Avalonia buildable while Flutter is made functionally equivalent to the currently supported native-audio workflows. Retire it only after parity, cross-platform tests, packaging verification and owner review.
- The Flutter direction is mandatory unless the owner explicitly changes it. Mandatory direction does not waive tests, code review, ABI-safety or real-time audio requirements.

**Consequences:**
- One cross-language native contract remains the boundary between UI and engine. New native functionality must be exposed through reviewed ABI additions and synchronized documentation/tests.
- `csbindgen` continues to serve the transitional C# frontend; Dart requires a separate `dart:ffi` wrapper and layout/error tests.
- The migration is staged to protect real audio functionality: the current Flutter workspace remains mock-only until the engine adapter and workflow parity are verified.
- Current implementation details, exact ABI inventory and migration acceptance gates live in [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md) and [`AI_HANDOFF.md`](AI_HANDOFF.md).

---

## Historical note — transport stabilization (2026-10-16)

Earlier documentation recorded a Stop/playhead inconsistency as an active bug. The maintainer subsequently reported that the core Stop fix and regression test were in place. Do not treat the older note as proof of a current unresolved bug; re-check the latest tests and runtime evidence before changing its status. This historical note does not alter the Rust real-time safety rules.

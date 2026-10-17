# Architecture Decision Records (ADRs): Aetherband

## Index of Decisions

- [ADR-001: Desktop-First Architecture with Decoupled Mobile Companion](#adr-001-desktop-first-architecture-with-decoupled-mobile-companion)
- [ADR-002: Rust Audio/DSP Core with Flutter Desktop Frontend](#adr-002-rust-audiodsp-core-with-flutter-desktop-frontend)
- [ADR-003: Lock-Free SPSC Ring Buffers for Audio Thread Synchronization](#adr-003-lock-free-spsc-ring-buffers-for-audio-thread-synchronization)
- [ADR-004: Versioned C ABI with Dart FFI](#adr-004-versioned-c-abi-with-dart-ffi)
- [ADR-005: Encapsulated AudioBackend Trait over Direct cpal Coupling](#adr-005-encapsulated-audiobackend-trait-over-direct-cpal-coupling)
- [ADR-006: Bundled Zip Container (.dawproject) for Project Files](#adr-006-bundled-zip-container-dawproject-for-project-files)
- [ADR-007: High-Quality Internal DSP First; Defer External Plugin Hosting](#adr-007-high-quality-internal-dsp-first-defer-external-plugin-hosting)

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

### ADR-002: Rust Audio/DSP Core with Flutter Desktop Frontend
- **Status:** Superseded by the Flutter migration decision
- **Original date:** 2026-10-16
- **Updated:** 2026-10-17
- **Context:**
  The initial UI decision selected C# / Avalonia. The project owner subsequently chose Flutter for the full-scale Windows/macOS desktop UI. The audio engine must remain independent of the presentation framework.
- **Decision:**
  Keep audio I/O, decoding, mixing, DSP, and real-time scheduling in Rust. Use Flutter/Dart for the desktop UI and Dart FFI over the versioned C ABI. The former Avalonia frontend has been removed from the desktop application.
- **Consequences:**
  - One maintained desktop UI instead of duplicated frontend implementations.
  - Custom arrangement/mixer presentation remains in Dart; real-time audio stays native.
  - Native FFI ownership, ABI versioning, lifecycle, and cross-platform packaging require explicit tests.
  - This decision does not claim the Flutter frontend has feature parity or that real playback is fully verified.

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

### ADR-004: Versioned C ABI with Dart FFI
- **Status:** Approved
- **Date:** 2026-10-17
- **Context:**
  Flutter needs a stable, testable boundary to the native Rust engine. Managed UI code must not depend on private Rust implementation details, and ABI drift must be detected before creating native resources.
- **Decision:**
  Keep the flat `extern "C"` ABI in `bindings/c_abi/src/lib.rs`; consume it from Flutter through Dart `dart:ffi`. Validate `daw_get_api_version()` before other calls, mirror `#[repr(C)]` layouts exactly, check return codes, and serialize access to each engine handle. The former `csbindgen` C# binding generation is no longer part of the desktop build.
- **Consequences:**
  - The C ABI remains the stable boundary between Rust and Flutter.
  - Dart FFI bindings must be tested against the actual Rust exports and native library on Windows/macOS.
  - API contract changes must update Rust, Dart and documentation together; do not assume `csbindgen` generates Dart bindings.

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
\n\n## Current implementation note — transport stabilization (2026-10-16)\n\nThe audio core uses a bounded SPSC command queue; the UI's immediate timer reset is not authoritative evidence that Stop was processed. A runtime report indicates that audio continues after the visible playhead resets. This is a bug to diagnose, not an intended design decision. Add regression tests and verify command acceptance, callback handling, output silence, decoder rewind/restart, and UI telemetry before closing the stabilization gate. Do not add locks, blocking calls, or heap allocation to the audio callback to work around it.\n
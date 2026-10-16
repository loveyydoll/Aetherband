# System Architecture: Aetherband

## 1. Target Architecture — Flutter + Rust via C ABI

**Mandatory product direction (2026-10-17):** implement Flutter/Dart as the full-scale primary desktop UI. The existing C#/Avalonia app is the transition frontend and remains available until the Flutter client has real engine integration and passes feature-parity/release gates. See [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md).

The intended architecture is a decoupled presentation/client layer, native interoperability boundary, and Rust engine:

1. **Flutter presentation layer (Dart):** owns user experience, app menu, timeline editing surface, browser/library, instrument/effect panels, mixer layout, keyboard shortcuts, view state and user preferences.
2. **Dart FFI adapter:** exposes a small typed engine-client interface and calls only exported functions in `bindings/c_abi/src/lib.rs`. It maps ABI layouts, handles and return codes and owns the serialized call boundary.
3. **Flat C ABI:** owns the language-neutral public boundary to the native engine. C-compatible structs and opaque handles are the only native data structures visible to the UI.
4. **Rust native engine:** owns audio processing, DSP, decoding, audio-device I/O, mixer, and all real-time-critical execution.

```mermaid
flowchart TD
    UI[Flutter / Dart desktop UI]
    Client[Engine client]
    FFI[Dart FFI wrapper]
    ABI[Flat C ABI facade]
    Engine[Rust DAWEngine]
    Workers[Background decoder workers]
    RT[Real-time audio callback / mixer / DSP]
    Device[cpal + operating-system audio device]
    UI --> Client --> FFI --> ABI --> Engine
    Engine --> Workers
    Engine --> RT --> Device
    Engine --> ABI
    ABI --> FFI --> Client --> UI
    Legacy[C# / Avalonia transition frontend]
    Legacy -. existing csbindgen-generated P/Invoke .-> ABI
```

**Implementation state:** the current Flutter workspace is still mock-only. Its transport, meter values, track/clip models and displayed waveforms are not native engine state. The diagram above is the required target architecture, not a claim that the Dart FFI adapter already exists.

### Native engine remains authoritative

- `core/` owns real-time processing, device streams, decoder workers and mixer state.
- `bindings/c_abi/src/lib.rs` is the authoritative list of exported functions and ABI layouts. Do not copy stale example signatures from older docs.
- `bindings/c_abi/build.rs` runs `csbindgen` for the existing C# frontend. That does not generate Dart bindings.
- If Flutter needs an operation not present in the C ABI, implement/review it on the native side and update the API contract, Dart wrapper, C# generated bindings (where applicable), and tests together.
- Do not implement DSP, file decoding, device callbacks, or raw-audio processing in Dart.

---

## 2. Component Responsibilities & Boundaries

### 2.1 Flutter presentation layer (target; currently under `prototypes/aetherband-flutter-ui/`)
- **Responsibilities:**
  - Render the desktop workstation at interactive refresh rates, with an arrangement-first layout, browser/library, instrument/effect panels, mixer and menus.
  - Keep UI/domain models separate from native engine handles behind an injectable engine-client interface.
  - Reflect native return codes and polled telemetry rather than assuming that a local button state means playback or a mix change succeeded.
  - Store view-only preferences (window layout, recent-file UI, zoom and panel visibility) separately from native audio state.
- **Prohibitions:**
  - **Zero audio processing:** never calculate DSP, decode media, mix samples or manipulate device buffers in Dart.
  - **Zero blocking FFI:** no long-running native or disk operation on the UI isolate.
  - Until concurrency guarantees are redesigned and tested, serialize calls for one engine handle through one owner boundary/isolate.
  - Do not ship the mock engine as if it were a real audio backend.

### 2.2 The C-ABI interoperability layer (`bindings/c_abi/`)
- **Responsibilities:**
  - Expose only deliberate `extern "C"` functions and `#[repr(C)]` layouts with documented ownership, return codes and lifetimes.
  - Provide opaque `DAWEngine` handles and ensure native allocations/resources are released through Rust exports.
  - Keep the actual function inventory in `bindings/c_abi/src/lib.rs` synchronized with `docs/API_CONTRACT.md` and the Dart adapter tests.
  - Continue generating C# P/Invoke declarations with `csbindgen` for the legacy frontend until it is retired.
- **Prohibitions:**
  - Do not pass C#/Dart objects, closures, UI handles or Rust internals across the boundary.
  - Do not move continuous raw audio samples through UI event handlers.
  - Do not assume `csbindgen` generates Dart bindings; Dart requires its own adapter.

### 2.3 The Core Engine (`core/`)
- **Responsibilities:**
  - Owning the audio device stream (`cpal` backend) and managing stream life-cycle.
  - Managing lock-free Single-Producer Single-Consumer (SPSC) ring buffers.
  - Scheduling sample-accurate events (e.g., volume ramps, playback start/stop).
  - Pre-allocating all audio buffers and lookup tables ahead of time.
  - Decoding audio files asynchronously on worker threads.
- **Sub-modules:**
  - `core::audio`: Processing graph, channel routing, buffer slicing.
  - `core::dsp`: Pure mathematical functions (oscillators, biquad filters, gain ramping, peak/RMS detectors).
  - `core::device`: Abstraction over OS audio APIs.
  - `core::transport`: Musical time, sample counters, tempo.
  - `core::ringbuf`: Thread-safe, wait-free ring buffer implementations.
  - `core::project`: Serializable schema and state models.

---

## 3. Data Flow Architecture

The application has three distinct paths. Flutter handles presentation and high-level control; the C ABI is the only Flutter-to-engine integration boundary; Rust owns audio-thread execution.

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Aetherband desktop target                      │
├───────────────────────┬──────────────────────┬──────────────────────┤
│ 1. Control path       │ 2. Telemetry path    │ 3. Audio path        │
│ Flutter -> Dart FFI   │ Rust -> Dart FFI     │ Disk -> Rust -> I/O  │
├───────────────────────┼──────────────────────┼──────────────────────┤
│ UI engine client      │ Poll exported frame  │ Worker decodes into  │
│ calls real exported   │ with bounded cadence │ bounded/prepared     │
│ C ABI functions       │ and updates view     │ native buffers       │
│ checks return codes   │ state                │ Audio callback reads │
│ keeps one owner path  │ no busy loop         │ without UI calls     │
└───────────────────────┴──────────────────────┴──────────────────────┘
```

### 3.1 Control path (Flutter to engine)

1. The user performs a DAW action, such as pressing Play or dragging a track fader.
2. A testable engine-client abstraction routes the action to the Dart FFI adapter.
3. The adapter invokes an actual exported function from `bindings/c_abi/src/lib.rs` (for example, `daw_engine_play` or `daw_engine_set_track_volume`) and checks the returned integer status.
4. The UI reports failure when a call is rejected/failed; it does not assume a local animation means the engine action succeeded.
5. Audio-thread processing and internal queueing stay inside Rust. Flutter must not call private core methods or push internal Rust commands directly.

The current ABI does not export `daw_engine_send_command` or a general-purpose `DAWCommand` struct at this snapshot. Follow [`API_CONTRACT.md`](API_CONTRACT.md), which is reconciled with the actual exported source functions.

### 3.2 Telemetry path (engine to Flutter)

1. Rust provides a `DAWMeteringFrame` through `daw_engine_poll_telemetry`.
2. The frame includes peak/RMS left/right, playhead frame, total duration frames and status flags as defined by the current C ABI.
3. The Flutter engine client polls at a bounded UI cadence and updates the view models/widgets.
4. Handle “no telemetry frame yet,” invalid handle and engine/device errors. Do not busy-loop and do not fabricate real telemetry in production mode.
5. Until the ABI's concurrency guarantees are deliberately expanded and tested, serialize telemetry polling with other calls on the same engine handle.

### 3.3 Audio Streaming Pipeline

1. Audio files are opened by a background `DiskReaderWorker` thread.
2. The worker thread decodes audio chunks into pre-allocated memory arenas.
3. The real-time audio thread reads from this pre-filled arena.
4. Under no circumstances does the audio thread ever open a file, read a byte from disk, or allocate memory.

---

## 4. Key Architectural Trade-Offs & Decisions

| Decision | Alternative Considered | Chosen Approach | Rationale |
| :--- | :--- | :--- | :--- |
| **Separation of Mobile & Desktop** | Single UI optimized for desktop and mobile at once | **Flutter desktop-first flagship; consider mobile as a separate effort later** | Allows a high-density desktop workstation without delaying the desktop migration for touch-first/mobile requirements. |
| **Language Selection** | Pure C++20 or managed audio/DSP | **Rust (engine) + Flutter/Dart (target UI)** | Keeps real-time engine execution native; Flutter owns presentation/control through the flat C ABI. Existing C# remains transitional. |
| **Audio Thread Communication** | Shared `Arc<Mutex<EngineState>` from the UI | **Bounded native engine protocol / SPSC where implemented** | The UI calls the C ABI from a serialized control boundary; all audio-thread communication remains inside Rust and must preserve real-time constraints. |
| **Plugin Architecture** | Immediate VST3 hosting | **Built-in DSP first; defer external plugins to Phase 5** | VST3 hosting is notoriously complex, prone to third-party crashes, and legally complicated. Built-in DSP guarantees stability. |
| **Serialization Format** | Monolithic binary blob | **Standard JSON / MessagePack metadata + assets folder inside zip** | Readable, robust against version changes, easy to inspect and debug, highly portable. |

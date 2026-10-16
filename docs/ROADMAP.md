# Development Roadmap: CustomDAW

## 1. Roadmap Overview & Milestones

The roadmap follows an incremental, test-driven progression designed to prove the hardest systems-engineering problems (real-time audio safety and cross-language FFI) before building higher-level features.

```
Phase 0: Planning & Setup ──► Phase 1: Real-Time Core ──► Phase 2: Desktop MVP
                                                                 │
Phase 5: Extensibility   ◄── Phase 4: Recording & Mix ◄── Phase 3: Timeline & Disk
```

---

## 2. Phase Breakdown

### Phase 0 — Planning and Validation (Current Phase)
- **Goals:** Establish architecture, project requirements, C-ABI contracts, and environment setup.
- **Prerequisites:** None.
- **Deliverables:**
  - Architecture documents in `docs/`.
  - Toolchain installation guidelines for Windows.
  - Initial repository layout and `.gitignore`.
- **Exit Criteria:** Architectural documents reviewed and approved; local developer tools installed.

---

### Phase 1 — Real-Time Audio Core Foundation
- **Goals:** Build the pure Rust audio engine core, stream I/O abstraction, and real-time safety harness.
- **Prerequisites:** Phase 0 completion.
- **Deliverables:**
  - `core/` Rust workspace with `cpal` audio backend.
  - Hardware device enumeration and default stream initialization (WASAPI on Windows, CoreAudio on macOS).
  - Allocation-free real-time audio callback executing a pure Sine Wave generator with click-free gain ramping.
  - Lock-free Single-Producer Single-Consumer (SPSC) ring buffers (`rtrb`) for commands and metering.
  - Automated headless test suite with `assert_no_alloc`.
- **Acceptance Criteria:**
  - `cargo test` passes 100%.
  - Headless test executes 100,000 continuous audio blocks without a single dynamic memory allocation.
  - Audio callback runs under 2.0 ms execution time at 128-sample buffer.
- **Risks:** Operating system audio permissions and driver differences.

---

### Phase 2 — Desktop MVP (First Cross-Language Integration)
- **Goals:** Connect the Rust audio core to the C# Avalonia desktop user interface.
- **Prerequisites:** Phase 1 completion.
- **Deliverables:**
  - `bindings/c_abi` native library export (`daw_core.dll` / `libdaw_core.dylib`).
  - Automated C# P/Invoke bindings generated via `csbindgen`.
  - Avalonia desktop application with:
    - Audio device selection dialog.
    - Transport toolbar (Play, Pause, Stop buttons).
    - Master volume slider with de-zippering gain ramping.
    - 60 FPS real-time stereo VU meter.
    - Stereo WAV file playback button.
- **Acceptance Criteria:**
  - Desktop app builds and launches on Windows and macOS.
  - Changing volume rapidly generates zero clicks, pops, or audio dropouts.
  - VU meter animates smoothly in sync with audio output.
  - Exiting the application shuts down the audio stream cleanly without crashing or hanging.
- **Risks:** FFI data alignment or missing native DLL path during runtime.

---

### Phase 3 — Multi-Track Timeline & Disk Streaming
- **Goals:** Enable multi-track arrangement, asynchronous disk streaming, and waveform rendering.
- **Prerequisites:** Phase 2 completion.
- **Deliverables:**
  - Background disk reader worker thread (`symphonia` decoder).
  - Double-buffered audio streaming into pre-allocated memory arenas.
  - Sample-accurate arrangement timeline engine.
  - Avalonia timeline view with horizontal zooming, track headers, and vector waveform rendering.
- **Acceptance Criteria:**
  - Simultaneous playback of 16 stereo audio tracks at 48 kHz / 24-bit with under 30% CPU load.
  - Smooth timeline scrolling at 60+ FPS during active audio playback.

---

### Phase 4 — Audio Recording, Mixer & Project Serialization
- **Goals:** Support microphone/line recording, mixing console, and saving/loading projects.
- **Prerequisites:** Phase 3 completion.
- **Deliverables:**
  - Low-latency audio input recording path with background disk writer.
  - Multi-channel mixer with faders, mute, solo, and Equal Power pan laws.
  - `.dawproject` file serializer/deserializer (ZIP bundle with `project.json` and `assets/`).
  - Autosave and crash recovery system.
  - Offline master bounce export to 24-bit WAV.
- **Acceptance Criteria:**
  - Record external microphone input into an audio track, save project to disk, restart app, reload, and verify identical playback.
  - Offline bounce renders a 3-minute arrangement to a stereo WAV file in under 10 seconds.

---

### Phase 5 — MIDI, Software Instruments, and Plugins
- **Goals:** Expand into composing with MIDI, virtual instruments, and third-party plugins.
- **Prerequisites:** Phase 4 completion.
- **Deliverables:**
  - Sample-accurate MIDI event scheduling and piano roll editor.
  - Built-in polyphonic subtractive synthesizer and drum sampler.
  - Studio DSP effect suite (Parametric EQ, Compressor, Delay, Reverb).
  - Plugin hosting abstraction starting with **CLAP** (CLever Audio Plugin), followed by **VST3**.
- **Acceptance Criteria:**
  - Record MIDI from a USB keyboard, quantize notes, play through internal synth, and host an external CLAP plugin.

---

### Phase 6 — Native Mobile Companion DAW (Separate Standalone Effort)
- **Goals:** Build the mobile companion DAW for iOS, iPadOS, and Android reusing the `daw_core` Rust engine and opening `.dawproject` files.
- **Prerequisites:** Desktop DAW mature and stable (Phase 4+).
- **Deliverables:**
  - Standalone mobile repository or mobile workspace consuming `daw_core`.
  - Swift / SwiftUI frontend on iOS/iPadOS; Kotlin / Jetpack Compose on Android.
  - Touch-first arrangement, drum pads, and mobile audio session management.

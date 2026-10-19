# System Requirements: Aetherband

**Scope update (2026-10-19):** Windows desktop is the only current target. These requirements are the product backlog, not a claim that every item exists. For implemented versus missing features and current evidence, use [Feature Tracker](FEATURE_TRACKER.md) and [Project State](PROJECT_STATE.md). Other platforms are deferred.

## 1. Functional Requirements

### 1.1 Audio Engine & Hardware I/O
- **FR-1.1 (P0): Device Enumeration & Selection:** The engine must query and list all available audio output and input devices on the host operating system, reporting device names, default sample rates, and supported buffer sizes.
- **FR-1.2 (P0): Stream Lifecycle Management:** The engine must reliably open, start, pause, stop, and close audio streams without crashing or leaving devices in a locked state.
- **FR-1.3 (P0): Device Disconnection Handling:** When an active audio output device is unplugged or switched by the OS, the engine must safely pause playback and notify the UI without crashing.
- **FR-1.4 (P0): Real-Time Test Signal Generation:** The engine must provide an internal pure Sine Wave oscillator with adjustable frequency (20 Hz – 20 kHz) and amplitude (-60 dB to 0 dB) for pipeline verification.
- **FR-1.5 (P1): Audio File Decoding & Streaming:** The engine must decode and stream audio files from disk through an asynchronous ring-buffer. WAV playback has been tested; FLAC, MP3, AIFF, OGG, and AAC/M4A are candidates based on the decoding stack and must be confirmed against the implemented decoder configuration and end-to-end tests.
- **FR-1.6 (P1): Multi-Track Summing & Panning:** The engine must sum multiple simultaneous audio tracks into a master stereo bus using standard pan laws (Equal Power -3 dB).
- **FR-1.7 (P2): Audio Recording:** The engine must record incoming audio from an input device, writing uncompressed 24-bit/32-bit float WAV data to disk on a background thread.
- **FR-1.8 (P2): Sample-Rate Conversion:** The engine must dynamically resample audio assets matching the active hardware output rate using high-quality sinc interpolation.

### 1.2 Transport & Timeline
- **FR-2.1 (P0): Transport Controls:** Play, Pause, Stop and Seek must produce immediate, observable engine behavior. Stop must silence the output, reset the playhead and allow a subsequent Play to restart from the beginning. The Stop fix is reported complete; keep acceptance/verification evidence current and do not describe the original regression as active unless reproduced.
- **FR-2.2 (P1): Timeline & Musical Grid:** Support sample-accurate playhead tracking, beats-per-minute (BPM) tempo configuration, and musical time signatures (e.g., 4/4, 3/4).
- **FR-2.3 (P1): Clip Arrangement:** Support placing, moving, splitting, trimming, and looping audio clips on discrete tracks.

### 1.3 User Interface (Desktop)
- **FR-3.1 (P0): Real-Time Metering:** Render stereo Peak and RMS volume levels at $\ge 60\text{ FPS}$ with smooth decay physics.
- **FR-3.2 (P0): Master Volume Fader:** Adjust master gain with de-zippering/smoothing to prevent audible stepping artifacts.
- **FR-3.3 (P1): Waveform Display:** Render visual audio waveforms for clips with multi-resolution peak caching.
- **FR-3.4 (P1): Device Configuration Dialog:** Allow the user to select input/output devices, sample rates (44.1 kHz, 48 kHz, 96 kHz), and buffer sizes (64, 128, 256, 512, 1024 frames).

### 1.4 Project Persistence & Export
- **FR-4.1 (P1): Project Serialization:** Save and load project metadata (tracks, clip locations, tempo, mixer volumes) into a versioned format (`.dawproject`).
- **FR-4.2 (P2): Offline Master Bounce:** Render the entire arrangement to a 24-bit 48 kHz stereo WAV file faster than real-time.

---

## 2. Non-Functional Requirements

### 2.1 Real-Time Audio Constraints (Hard Constraints)
- **NFR-1.1 (Zero Heap Allocation):** The real-time audio callback running on the dedicated OS audio thread must perform **zero** dynamic memory allocations or deallocations (`malloc`, `free`, `Vec::push`, `Box::new`). All buffers must be pre-allocated.
- **NFR-1.2 (Lock-Free Synchronization):** The audio callback must **never** acquire an operating system mutex or blocking lock (`std::sync::Mutex`, critical section). All communication with other threads must use wait-free Single-Producer Single-Consumer (SPSC) ring buffers.
- **NFR-1.3 (Zero Blocking I/O):** The audio callback must never perform disk reads, writes, socket operations, or operating system logging.
- **NFR-1.4 (Real-Time Budget):** At 48 kHz with a 128-sample buffer, the maximum allowed execution time per callback block is **$2.0\text{ ms}$** (leaving a 0.67 ms safety margin below the hard 2.67 ms deadline).

### 2.2 Performance & Responsiveness
- **NFR-2.1 (UI Frame Rate):** The desktop interface must render at a consistent 60 FPS (or display refresh rate up to 144 Hz) without stutter during continuous audio playback.
- **NFR-2.2 (Control Latency):** Transport commands (Play, Stop, Fader adjustments) sent from the UI must take effect in the audio engine within one audio buffer cycle ($< 10\text{ ms}$).
- **NFR-2.3 (Memory Footprint):** Idle memory consumption of the desktop application must remain under $150\text{ MB}$.

### 2.3 Windows & Build
- **NFR-3.1 (Supported OS Versions):** Windows 10 (version 1903+) and Windows 11 (64-bit x86_64) are the intended target. The current validation runner is Windows; runtime support must still be checked on each supported Windows release.
- **NFR-3.2 (Clean Build System):** The core engine must compile with standard Cargo commands, and the desktop application must build with Flutter for Windows.

---

## 3. Platform-Specific Audio Requirements

### Windows
- **Driver Model:** Support **WASAPI Shared** (default, universally compatible) and **WASAPI Exclusive** (low latency, bypasses Windows mixer).
- **Extensibility:** Architecture must accommodate a future **ASIO** driver backend for professional audio interfaces via an optional compile-time feature.
- **Binary Format:** Core engine compiles as a 64-bit dynamic link library (`daw_core.dll`).

### Other platforms
macOS, Linux, mobile and web builds are deferred. Their requirements must be revisited if the Windows audio and session workflows prove stable and platform scope changes.

---

## 4. Priority Matrix

**Current evidence (2026-10-19):** Rust transport tests cover Stop silence/playhead reset and the opt-in Windows WASAPI smoke confirms stream pause/shutdown. Flutter tests and human listening remain separate checks; use the Feature Tracker for current verification state.

| Feature / Area | Priority | Target Milestone |
| :--- | :--- | :--- |
| Audio device discovery & stream start/stop | **P0 (Critical)** | MVP (Phase 1–2) |
| Allocation-free real-time audio callback | **P0 (Critical)** | MVP (Phase 1) |
| Sine oscillator & click-free gain fader | **P0 (Critical)** | MVP (Phase 1–2) |
| Lock-free metering stream (Peak/RMS) | **P0 (Critical)** | MVP (Phase 1–2) |
| Flutter desktop shell with live engine meters | **P0 (Critical)** | MVP (Phase 2) |
| Audio file decoder & background streaming | **P1 (High)** | Phase 3 |
| Multi-track arrangement timeline & waveforms | **P1 (High)** | Phase 3 |
| Project save/load format (`.dawproject`) | **P1 (High)** | Phase 4 |
| Audio recording from microphone/line-in | **P2 (Medium)** | Phase 4 |
| Offline master bounce export (WAV) | **P2 (Medium)** | Phase 4 |
| Third-party plugin hosting (CLAP / VST3) | **P3 (Future)** | Phase 5 |

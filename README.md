# 🎰 Aetherband

> **A modern, open-source desktop Digital Audio Workstation engineered for flow, speed, and hard real-time precision.**

RouletteStudio bridges the gap between intuitive songwriting sketchpads and high-precision production environments. It combines the immediate, distraction-free workflow of modern creative apps with the low-latency, deterministic audio processing expected of a professional workstation.

---

> [!WARNING]
> ### 🚧 Work in Progress (Early Alpha)
> RouletteStudio is under active, rapid development and is currently in **early alpha**.
> - APIs, project formats, and interfaces are evolving quickly and subject to breaking changes.
> - While core audio playback and multi-track mixing are functional and backed by real-time safety tests, advanced features (MIDI recording, plugin hosting, automation, and project saving) are in active development.
> - **Not recommended for production work yet.** Use it to test, experiment, and contribute!

---

## 🧐 What Can It Do Right Now? (For the Average User)

If you download and run RouletteStudio today, here is an honest, plain-English breakdown of what is working versus what is still being built:

### ✅ What You Can Do Right Now:
- **Import Multiple Audio Files:** Load common audio file formats (**WAV, FLAC, MP3, OGG, AAC/M4A**) onto separate tracks by clicking `+ Add Audio Track`.
- **Automatic Format & Sample Rate Conversion:** Mix audio files of different sample rates (e.g. 44.1 kHz, 48 kHz, 96 kHz) together—the engine resamples them seamlessly in the background.
- **Multi-Track Playback:** Play, pause, and stop playback of all loaded tracks simultaneously in sync.
- **Track Mixing Controls:**
  - Adjust volume faders per track with real-time dB readouts and click-free volume smoothing.
  - Pan tracks left, right, or center with an equal-power stereo balance law.
  - Mute/unmute individual tracks on the fly.
  - Remove unwanted tracks from the session.
- **Master Bus Control & Metering:** Control master volume and monitor real-time stereo peak/RMS VU meters updating smoothly at 60 FPS.
- **Audio Device Selection:** Switch output devices (headphones, speakers, audio interfaces) directly from the top transport bar without restarting.

### ❌ What It Cannot Do Yet (Under Active Development):
- **No Saving or Loading Projects:** You cannot save your session to disk yet (session state resets when closing the app).
- **No Audio Recording:** Microphone/instrument audio recording via inputs is planned for Phase 4.
- **No Visual Waveform Peaks (Yet):** Track lanes currently show clip markers, but not drawn peak/RMS waveform outlines yet.
- **No MIDI, Virtual Instruments, or Piano Roll:** MIDI keyboard input, software synths, and sequencing will come in Phase 5.
- **No VST3 / CLAP / AU Plugins:** Audio effect and instrument plugin hosting will be introduced in Phase 6.
- **No Automation Curves:** Volume/pan cannot be automated along a curve yet.
- **No Exporting to WAV/MP3 ("Bounce/Render"):** Offline mixdown rendering is not yet implemented.

---

## 🚀 Current Milestone: Phase 2 & 3 (Multi-Track Playback & Arranger UI)

RouletteStudio has completed **Phase 1 (Real-Time Audio Core)** and **Phase 2 & 3 (Multi-Track Audio Playback, Disk Streaming & Timeline UI)**:

- [x] **Zero-Allocation Audio Thread:** Hardware callback loop executing on dedicated OS audio thread with guaranteed zero heap allocations.
- [x] **Hardware Audio Driver Support:** Low-latency device discovery and output stream management via `cpal` (WASAPI on Windows, CoreAudio on macOS).
- [x] **Background Disk Streaming & Decoding:** Non-blocking file decoding worker utilizing `symphonia` supporting **WAV, FLAC, MP3, OGG, and AAC/M4A**.
- [x] **Real-Time Sample Rate Conversion:** High-fidelity sinc/FFT resampling powered by `rubato`.
- [x] **64-Track Summing Mixer:** Real-time multi-track engine featuring Equal-Power stereo panning law and 256-sample de-zippering gain ramping.
- [x] **Lock-Free Concurrency:** Single-Producer Single-Consumer (SPSC) ring buffers (`rtrb`) for wait-free UI ⇄ Audio communications.
- [x] **Automated Safety Test Harness:** Automated enforcement of zero allocations across 100,000 continuous blocks via `assert_no_alloc`.
- [x] **Flat C-ABI & Automated Bindings:** Clean C99 FFI with automated type-safe C# P/Invoke generation (`csbindgen`).
- [x] **Modern Desktop App:** Hardware-accelerated desktop UI built with **.NET 10 LTS** and **Avalonia UI**, featuring multi-track lanes, track controls (Volume, Pan, Mute, Remove), playhead scrubber, timeline counter, and live stereo VU meters.

---

## ⚡ Highlights

- **Hard Real-Time Audio Engine:** Engineered in pure **Rust** with zero-allocation audio callbacks and wait-free concurrency (`rtrb`), eliminating dropouts, clicks, and priority inversions.
- **Hardware-Accelerated UI:** Built in **C# (.NET 10 LTS)** with **Avalonia UI**, delivering fluid 60–120 FPS timeline scrolling and vector waveforms on Windows and macOS.
- **Desktop-First Precision:** Designed specifically for desktop workflows—dense mixer strips, multi-monitor layouts, keyboard shortcuts, and sample-accurate editing.
- **Self-Contained Projects:** Portable `.dawproject` format planned to bundle project metadata and audio assets, eliminating "missing audio file" headaches.
- **Open-Source & Extensible:** Free software under the GPLv3 license, built with a clean modular separation between core DSP and UI presentation.

---

## 🛠️ Architecture at a Glance

```
┌────────────────────────────────────────────────────────┐
│                   RouletteStudio                       │
├───────────────────────────┬────────────────────────────┤
│  Desktop Presentation     │  Shared Audio Engine       │
│  (C# .NET 10 + Avalonia)  │  (Rust Core Library)       │
├───────────────────────────┼────────────────────────────┤
│ • GPU-Accelerated Skia    │ • Hardware Callback Loop   │
│ • ReactiveUI / MVVM       │ • Lock-Free SPSC Queues    │
│ • Multi-Track Arranger    │ • Equal-Power Pan Mixer    │
│ • Track Control Strips    │ • Symphonia Disk Streaming │
│ • Live Stereo VU Meters   │ • Rubato Resampling (SRC)  │
└─────────────▲─────────────┴─────────────▲──────────────┘
              │                           │
              └───────[ Flat C-ABI ]──────┘
                 (csbindgen P/Invoke)
```

- **Core & DSP:** Rust (`cpal` backend, `symphonia` decoder, `rubato` SRC, `rtrb` lock-free queues)
- **Desktop Frontend:** C# (.NET 10 LTS) + Avalonia UI (v11+)
- **Interoperability:** Flat C99 ABI with automated type-safe bindings (`csbindgen`)

---

## 📁 Repository Structure

```
RouletteStudio/
├── Cargo.toml                       # Root Rust workspace (core + bindings)
├── core/                            # Pure Rust audio engine & DSP library
│   ├── src/
│   │   ├── audio.rs                 # Allocation-free audio callback processor & mixer
│   │   ├── decoder.rs               # Background disk streaming & file decoder (symphonia)
│   │   ├── device.rs                # Hardware discovery & cpal stream backend
│   │   ├── dsp.rs                   # Sine oscillator, gain ramp, level meter
│   │   ├── ringbuf.rs               # Lock-free SPSC queues (rtrb)
│   │   ├── track.rs                 # Real-time TrackPlayer & TrackSlots
│   │   └── lib.rs                   # High-level DAWEngine controller
│   └── tests/
│       └── realtime_safety.rs       # 100,000-block zero-allocation test harness
├── bindings/
│   └── c_abi/                       # Flat C-ABI export layer (daw_core.dll)
│       └── build.rs                 # Runs csbindgen to generate C# bindings
├── apps/
│   └── desktop/                     # Avalonia UI desktop application (.NET 10)
│       └── RouletteStudio.Desktop/  # Views, ViewModels, and AudioService
├── docs/                            # Comprehensive architectural blueprints & specifications
└── tools/                           # Automated build and execution scripts
    ├── build.ps1                    # One-command Rust + C# build script
    └── run.ps1                      # Builds and launches the desktop app
```

---

## 💻 Getting Started

### Prerequisites
1. **Rust Toolchain:** [rustup.rs](https://rustup.rs/) (stable MSVC on Windows).
2. **.NET 10 SDK:** [.NET 10 Download](https://dotnet.microsoft.com/download).
3. **Visual Studio:** Visual Studio 2022/2026 with *.NET desktop development* and *Desktop development with C++* workloads.

### Build Everything
Run the automated build script from PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build.ps1
```

### Launch the Desktop App
```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run.ps1
```
*(Or open `apps/desktop/RouletteStudio.slnx` in Visual Studio and press **F5**).*

### Run the Audio Core Test Suite
Run all unit tests and verify the 100,000-block zero-allocation guarantee:
```powershell
cargo test -p daw_core --tests
```

---

## 🗺️ Roadmap Overview

| Phase | Milestone | Status |
|:---:|---|:---:|
| **0** | Architectural Blueprint & Documentation (10 ADRs) | ✅ Complete |
| **1** | Real-Time Audio Core Foundation & Hardware I/O | ✅ Complete |
| **2** | Audio File Playback & Background Disk Streaming | ✅ Complete |
| **3** | Multi-Track Mixer & Interactive Timeline UI | ✅ Complete |
| **4** | Audio Recording & Waveform Peak Visualizer | ⏳ Upcoming |
| **5** | MIDI Engine, Piano Roll & Virtual Instruments | 📅 Planned |
| **6** | Mixer Routing, Effects Engine & Plugin Hosting | 📅 Planned |

---

## 📚 Documentation

Detailed blueprints and architectural specifications:

- [**VISION.md**](docs/VISION.md) — Product vision, target audience, and core principles.
- [**REQUIREMENTS.md**](docs/REQUIREMENTS.md) — Real-time performance and functional requirements.
- [**ARCHITECTURE.md**](docs/ARCHITECTURE.md) — System boundaries, thread boundaries, and data flow.
- [**AUDIO_ENGINE.md**](docs/AUDIO_ENGINE.md) — Real-time thread contract, latency calculations, and mixer design.
- [**API_CONTRACT.md**](docs/API_CONTRACT.md) — Flat C-ABI definitions and C# interop contract.
- [**ROADMAP.md**](docs/ROADMAP.md) — Complete 6-phase development roadmap.
- [**DECISIONS.md**](docs/DECISIONS.md) — Architecture Decision Records (ADRs).
- [**AI_WORKFLOW.md**](docs/AI_WORKFLOW.md) — AI pair-programming safety procedures.

---

## 📄 License

RouletteStudio is licensed under the [GNU General Public License v3.0 (GPLv3)](LICENSE).

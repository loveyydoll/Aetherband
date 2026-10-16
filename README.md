# 🎰 RouletteStudio

> **A modern, open-source desktop Digital Audio Workstation engineered for flow, speed, and hard real-time precision.**

RouletteStudio bridges the gap between intuitive songwriting sketchpads and high-precision production environments. It combines the immediate, distraction-free workflow of modern creative apps with the low-latency, deterministic audio processing expected of a professional workstation.

---

## 🚀 Current Status: Phase 2 & 3 Active

RouletteStudio has completed **Phase 1: Real-Time Audio Core Foundation** and **Phase 2 & 3: Multi-Track Playback, Disk Streaming, and Visual Timeline**.

- [x] Allocation-free real-time audio callback running on high-priority OS threads.
- [x] Hardware audio device discovery and streaming via `cpal` (WASAPI on Windows, CoreAudio on macOS).
- [x] Background lock-free audio decoding using `symphonia` (WAV, FLAC, MP3, OGG, AAC/M4A).
- [x] High-quality real-time sample rate conversion via `rubato`.
- [x] Multi-track summing mixer with Equal-Power panning law and smooth de-zippering gain ramps.
- [x] Wait-free lock-free Single-Producer Single-Consumer (SPSC) ring buffers (`rtrb`).
- [x] Automated real-time safety verification harness enforcing zero heap allocations via `assert_no_alloc` over 100,000 blocks.
- [x] Flat C-ABI interop layer with automated type-safe C# P/Invoke binding generation (`csbindgen`).
- [x] Hardware-accelerated desktop application running in **.NET 10 LTS** with **Avalonia UI**, interactive multi-track lane arranger, track strips (Volume, Pan, Mute, Remove), playhead scrubber, and live stereo VU meters.

---

## ⚡ Highlights

- **Hard Real-Time Audio Engine:** Engineered in pure **Rust** with zero-allocation audio callbacks and wait-free concurrency (`rtrb`), eliminating dropouts, clicks, and priority inversions.
- **Hardware-Accelerated UI:** Built in **C# (.NET 10 LTS)** with **Avalonia UI**, delivering fluid 60–120 FPS timeline scrolling and high-DPI vector waveforms on Windows and macOS.
- **Desktop-First Precision:** Designed specifically for desktop workflows—dense mixer strips, multi-monitor layouts, keyboard shortcuts, and sample-accurate mouse editing.
- **Self-Contained Projects:** Portable `.dawproject` format that bundles project metadata and audio assets, eliminating "missing audio file" nightmares when moving across machines.
- **Open-Source & Extensible:** Free software under the GPLv3 license, built with a clean modular architecture separating the core audio DSP from the user interface.

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
│ • High-DPI Waveforms      │ • Equal-Power Pan Mixer    │
│ • Live Stereo VU Meters   │ • Anti-Zipper Gain Ramping │
└─────────────▲─────────────┴─────────────▲──────────────┘
              │                           │
              └───────[ Flat C-ABI ]──────┘
                 (csbindgen P/Invoke)
```

- **Core & DSP:** Rust (`cpal` backend, lock-free SPSC queues, SIMD-accelerated math)
- **Desktop Frontend:** C# (.NET 10 LTS) + Avalonia UI (v11+)
- **Interoperability:** Flat C99 ABI with automated type-safe bindings (`csbindgen`)
- **Future Companion:** Standalone mobile companion DAW planned for iOS/iPadOS and Android reusing the shared Rust core.

---

## 📁 Repository Structure

```
RouletteStudio/
├── Cargo.toml                       # Root Rust workspace (core + bindings)
├── core/                            # Pure Rust audio engine & DSP library
│   ├── src/
│   │   ├── audio.rs                 # Allocation-free audio callback processor
│   │   ├── device.rs                # Hardware discovery & cpal stream backend
│   │   ├── dsp.rs                   # Sine oscillator, gain ramp, level meter
│   │   ├── ringbuf.rs               # Lock-free SPSC queues (rtrb)
│   │   └── lib.rs                   # High-level DAWEngine controller
│   └── tests/
│       └── realtime_safety.rs       # 100,000-block zero-allocation test harness
├── bindings/
│   └── c_abi/                       # Flat C-ABI export layer (daw_core.dll)
│       └── build.rs                 # Runs csbindgen to generate C# bindings
├── apps/
│   └── desktop/                     # Avalonia UI desktop application (.NET 10)
│       └── RouletteStudio.Desktop/  # Views, ViewModels, and AudioService
├── docs/                            # Comprehensive architectural blueprints
└── tools/                           # Automated build and execution scripts
    ├── build.ps1                    # One-command Rust + C# build script
    └── run.ps1                      # Builds and launches the desktop app
```

---

## 💻 Getting Started

### Prerequisites
1. **Rust Toolchain:** [rustup.rs](https://rustup.rs/) (stable MSVC on Windows).
2. **.NET 10 SDK:** [.NET 10 Download](https://dotnet.microsoft.com/download).
3. **Visual Studio:** Visual Studio 2022/2026 with the *.NET desktop development* and *Desktop development with C++* workloads.

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

### Run the Real-Time Safety Test Suite
To verify the allocation-free audio thread contract across 100,000 continuous audio blocks:
```powershell
cargo test --workspace -- --nocapture
```

---

## 📚 Documentation

Detailed architectural blueprints and development specifications:

- [**VISION.md**](docs/VISION.md) — Product vision, intended users, and core principles.
- [**REQUIREMENTS.md**](docs/REQUIREMENTS.md) — Functional and non-functional real-time requirements.
- [**ARCHITECTURE.md**](docs/ARCHITECTURE.md) — System boundaries, data flow, and concurrency model.
- [**AUDIO_ENGINE.md**](docs/AUDIO_ENGINE.md) — Real-time thread contract, latency math, and mixer design.
- [**API_CONTRACT.md**](docs/API_CONTRACT.md) — C-ABI definitions and C# interop contract.
- [**ROADMAP.md**](docs/ROADMAP.md) — Staged milestones from Phase 0 to Phase 6.
- [**DECISIONS.md**](docs/DECISIONS.md) — Architecture Decision Records (ADRs).
- [**AI_WORKFLOW.md**](docs/AI_WORKFLOW.md) — AI pair-programming safeguards and testing procedures.

---

## 📄 License

RouletteStudio is licensed under the [GNU General Public License v3.0 (GPLv3)](LICENSE).

# 🎰 RouletteStudio

> **A modern, open-source desktop Digital Audio Workstation engineered for flow, speed, and hard real-time precision.**

RouletteStudio bridges the gap between intuitive songwriting sketchpads and high-precision production environments. It combines the immediate, distraction-free workflow of modern creative apps with the low-latency, deterministic audio processing expected of a professional workstation.

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
│ • Custom Timeline & Mixer │ • Anti-Zipper Gain Ramping │
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

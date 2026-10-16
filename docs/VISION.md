# Product Vision: Aetherband

## 1. Vision Statement

**Aetherband** is a modern, free, and open-source Digital Audio Workstation designed to bridge the gap between intuitive music creation and precision audio engineering. It combines:

1. **The Accessibility of Modern Creative Tools:** A streamlined, discoverable workflow inspired by the immediacy of mobile sketchpads (like GarageBand) where song ideas can be captured in seconds without menu-diving or cognitive friction.
2. **The Openness and Connected Workflow of Modern Cloud Tools:** A modular, lightweight project architecture designed for effortless sharing, asset portability, and future collaborative production (reminiscent of BandLab).
3. **The Precision and Extensibility of Professional Desktop DAWs:** Deterministic, low-latency audio processing, sample-accurate timeline scheduling, robust track routing, and support for industry-standard plugins and hardware audio interfaces (comparable to Bitwig or Reaper).

Aetherband is developed under an open-source model (GPLv3), engineered for long-term maintainability, community contributions, and cross-platform performance.

---

## 2. Intended Users

- **Bedroom Producers & Songwriters:** Musicians who want to quickly record vocals, acoustic instruments, or MIDI ideas without getting bogged down in complex multi-window routing before they can make music.
- **Content Creators & Podcasters:** Creators needing clean, reliable multi-track recording, voice-over processing, volume leveling, and export with zero bloat.
- **Aspiring Audio Engineers & Students:** Producers seeking a transparent, reliable environment to learn mixing, DSP, signal routing, and arrangement without subscription paywalls or proprietary lock-in.
- **Experienced Music Producers:** Power users who appreciate a lightweight, fast-loading, crash-resilient DAW with high-performance audio engine capabilities and clean parameter automation.

---

## 3. Core Principles

1. **Hard Real-Time Audio Integrity:** Audio playback and recording must never stutter, click, or drop out due to user interface actions, background saving, or memory management. The audio thread is sacred.
2. **Intuitive by Default, Deep on Demand:** Beginners should be able to press "Record" or drop an audio loop and hear sound immediately. Advanced routing, automation curves, and precision editing tools reveal themselves organically as the user's needs grow.
3. **Desktop-First Optimization:** The desktop application is designed natively for precision mouse, keyboard, and multi-monitor workflows on Windows and macOS. It does not compromise desktop density or ergonomics for mobile touchscreen parity.
4. **Mobile-Ready Architecture:** The core audio processing engine and project file format are platform-agnostic, so a future mobile DAW can reuse the Rust core and project format without weakening the desktop-first product.
5. **Full-Scale Flutter Desktop UI:** Flutter/Dart is the mandatory long-term Windows/macOS frontend. It must use Dart FFI over the existing flat C ABI; the Rust engine remains responsible for all audio/DSP. The current C#/Avalonia app remains a transition frontend until Flutter reaches real-audio feature parity and passes the migration gates. This is an explicit owner decision, not an optional prototype.
6. **Data Sovereignty & Non-Destructive Editing:** All user audio recordings and imported files are preserved non-destructively. Project files are versioned, human-readable, and self-contained to avoid lost audio dependencies.
7. **Transparent Open Source:** Clean code, modular architecture, explicit FFI boundaries, and zero telemetry or proprietary bloat.
5. **Data Sovereignty & Non-Destructive Editing:** All user audio recordings and imported files are preserved non-destructively. Project files are versioned, human-readable, and self-contained to avoid lost audio dependencies.
6. **Transparent Open Source:** Clean code, modular architecture, explicit FFI boundaries, and zero telemetry or proprietary bloat.

---

## 4. Long-Term Goals

- **Full Multi-Track Production Suite:** High-track-count audio recording, comping, pitch correction, non-destructive slip/slice editing, and flexible time-stretching.
- **Comprehensive Mixing Console:** Unlimited audio buses, sends/returns, side-chain routing, VCA faders, and high-precision visual metering (LUFS, True Peak, RMS).
- **Virtual Instruments & Synthesis:** Native polyphonic subtractive synth, sample-based drum machine, multi-sampler, and wavetable engine.
- **Built-in DSP Effects:** High-grade studio suite (Dynamic EQ, Linear-Phase Filters, Multiband Compressor, Convolution Reverb, Delay, Saturation).
- **Industry Plugin Hosting:** Full support for modern **CLAP** (CLever Audio Plugin) and **VST3** standards with crash sandboxing.
- **Companion Mobile Application:** A separate touch-optimized DAW for iPadOS, iOS, and Android that shares the Rust core and seamlessly exchanges project files with the desktop app.

---

## 5. Initial Scope (Desktop MVP)

The initial scope deliberately avoids attempting to build a full multi-track studio on Day 1. Instead, it proves the core architectural foundation:

- **Target Platforms:** Windows (10/11) and macOS (Intel & Apple Silicon).
- **Core Engine:** Rust audio pipeline capable of low-latency playback (128–512 sample buffers) with zero heap allocations during playback.
- **Driver Support:** Windows WASAPI (Shared and Exclusive) and macOS CoreAudio.
- **Audio Playback:** Real-time test tone generator and buffered stereo WAV file playback.
- **Desktop UI target (Flutter / Dart):** Full-scale compact DAW workstation with transport, arrangement, library, mixer/device panels and keyboard/mouse-first workflows. The current Flutter workspace is still a UI-only mock; native engine integration is a required migration stage.
- **Transition frontend:** The current C#/Avalonia app keeps the existing audio-connected workflows available during the Flutter migration.
- **Telemetry & Control:** Flutter communicates with the engine through a dedicated Dart FFI adapter over `bindings/c_abi/`. Keep internal command queues and audio-thread communication inside Rust.

---

## 6. Non-Goals for the Initial Stages

- **No Mobile Apps in Phase 1:** iOS, iPadOS, and Android development is explicitly deferred to a separate project phase after the desktop engine is proven and mature.
- **No Third-Party Plugin Hosting in Phase 1:** Third-party VST3/CLAP plugins will not be supported in early milestones; initial development focuses on internal signal generation and playback.
- **No Complex Cloud/Web Collaboration Initially:** No proprietary cloud lock-in or real-time multi-user web syncing in the MVP.
- **No Direct Audio Marshaling Across FFI:** UI will never process, receive, or modify raw audio sample buffers directly; all audio processing remains strictly inside Rust.

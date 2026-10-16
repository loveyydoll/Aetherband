# Technology Stack Evaluation: CustomDAW

## 1. Selected Technology Stack

| Layer | Technology | Version / Target | Rationale |
| :--- | :--- | :--- | :--- |
| **Audio & DSP Core** | **Rust** | 2021 Edition (stable) | Memory safety without garbage collection; zero-cost abstractions; compile-time thread safety; cross-compiles cleanly to Windows, macOS, iOS, Android. |
| **Audio I/O Driver** | **`cpal`** | Latest stable | Pure Rust multiplatform audio I/O library supporting WASAPI (Shared & Exclusive) on Windows and CoreAudio on macOS. |
| **Concurrency / Queues**| **`rtrb`** | Latest stable | Wait-free Single-Producer Single-Consumer (SPSC) ring buffer designed specifically for real-time audio threads. |
| **Real-Time Safety** | **`assert_no_alloc`** | Latest stable | Enforces zero dynamic memory allocations in automated CI audio test suites. |
| **Audio File Decoding** | **`symphonia`** | Latest stable | Pure Rust, memory-safe audio decoding library supporting WAV, FLAC, MP3, AAC, and OGG with zero C-library dependencies. |
| **Interoperability (FFI)**| **Flat C-ABI + `csbindgen`** | Latest stable | Flat C99 ABI with automated C# P/Invoke binding generation, preventing manual marshaling errors. |
| **Desktop Application** | **C# / .NET** | .NET 8 / 9 LTS | Strong performance, excellent productivity, aligns with primary developer expertise, and rich tooling. |
| **Desktop UI Framework**| **Avalonia UI** | v11+ | High-performance, GPU-accelerated Skia rendering, XAML styling, cross-platform on Windows and macOS. |
| **Build Tools** | **Cargo + MSBuild / dotnet** | Latest | Standard toolchains; clean scriptable automation without arcane C++ build systems. |

---

## 2. Alternatives Evaluated and Rejected

### 2.1 C++20 + JUCE
- **Description:** The legacy industry standard for audio plugins and DAWs (Tracktion, Bitwig's native engine).
- **Why Rejected:**
  - C++ lacks memory safety; dangling pointers and data races lead to silent memory corruption and hard-to-reproduce crashes.
  - Steep learning curve for a developer transitioning from C#.
  - JUCE licensing is restrictive: dual GPLv3 or expensive commercial subscription ($50–$150/mo per developer).
  - Heavy monolithic framework with high coupling.

### 2.2 Pure C# / Managed Audio Engine
- **Description:** Writing the audio callback directly in C# using .NET P/Invoke to WASAPI.
- **Why Rejected:**
  - .NET is a garbage-collected runtime. Even with modern optimizations (`Span<T>`, GC-free code paths, NativeAOT), the .NET runtime can trigger garbage-collection pauses, background finalizers, or thread suspension, causing unpredictable audio buffer under-runs (xruns) at low latencies ($\le 128$ frames).

### 2.3 Pure Rust UI (Slint / Makepad / egui)
- **Description:** Writing both the engine and the UI entirely in Rust to eliminate FFI.
- **Why Rejected:**
  - Rust GUI frameworks are still evolving rapidly.
  - Text editing, complex window docking, accessibility, and high-DPI platform conventions are significantly more mature in Avalonia UI.
  - Sacrifices the developer's core strength and productivity in C#.

---

## 3. Licensing Strategy

- **Core Engine (`daw_core`):** Licensed under **GPLv3** (with an option for dual-licensing).
  - Preserves open-source integrity, preventing proprietary closed-source commercial forks without giving back.
  - Compatible with open-source audio toolchains and dependencies (all selected Rust crates use MIT or Apache-2.0, which are compatible with GPLv3).
- **Dependencies License Audit:**
  - `cpal`: Apache-2.0 (Permissive, GPLv3 compatible).
  - `rtrb`: MIT / Apache-2.0 (Permissive, GPLv3 compatible).
  - `symphonia`: MPL-2.0 (Permissive, compatible).
  - `csbindgen`: MIT (Permissive, compatible).
  - `Avalonia`: MIT (Permissive, compatible).
- **No Steinberg proprietary SDK code** is checked into the core repository for the MVP, avoiding any proprietary license conflicts.

---

## 4. Decisions Requiring Early Prototype Validation

1. **`cpal` WASAPI Exclusive Latency on Windows:**
   - *Question:* Does `cpal` achieve stable $< 6\text{ ms}$ round-trip latency across consumer USB audio interfaces in WASAPI Exclusive mode without requiring a dedicated ASIO driver?
   - *Validation:* Will be measured directly in Phase 1 via a dedicated latency test harness.
2. **Avalonia 120 Hz Timeline Rendering Performance:**
   - *Question:* Does Avalonia's Skia rendering maintain 120 FPS when drawing multi-track vector waveforms with horizontal zoom?
   - *Validation:* Will be benchmarked in Phase 3 with a dedicated waveform stress test.

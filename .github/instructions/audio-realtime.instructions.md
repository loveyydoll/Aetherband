---
applyTo: "**/*.cpp, **/*.cc, **/*.cxx, **/*.hpp, **/*.h, **/*audio*, **/*decoder*, **/*ringbuf*, **/*device*"
---

# Real-Time Audio, Concurrency and Lifecycle Rules

These constraints override convenience or stylistic preferences whenever code may execute on the audio callback thread. They apply to the C++/JUCE target. Legacy Rust rules remain relevant when maintaining the old reference implementation.

## Audio callback contract

- Callback execution must be bounded: no unbounded loops, blocking waits, sleep, filesystem/network I/O, blocking logging, synchronous UI dispatch, or contended mutex/RwLock acquisition.
- Avoid unpredictable heap allocation/deallocation and arbitrary destructors on the callback. Use a documented ownership-transfer and deferred-reclamation design.
- Do not decode, seek files, resample, discover devices, compile graphs, or reconfigure streams from the callback.
- Handle channel count, sample rate, frame count, buffer capacity, malformed commands, and absent tracks explicitly. Define behavior for zero, mono, stereo, multichannel, and oversized buffers.
- Avoid exception/panic paths in callback-reachable code. Do not rely on debug-only assertions as runtime validation.
- JUCE abstractions do not automatically make a callback path real-time safe; inspect the operations and ownership used.

## Thread and queue contracts

For every cross-thread queue, document producer/consumer ownership, concurrency model, capacity, full-queue behavior, resource ownership on success/rejection/shutdown, deferred reclamation, and behavior when consumers or workers stop unexpectedly.

Never silently replace a bounded non-blocking path with a blocking lock or unbounded queue. Do not label a queue lock-free or wait-free without verifying its implementation and usage.

## Decoder and device lifecycle

- Decoding, seeking, file access, and resampling setup belong off the callback.
- Define the protocol for Play, Pause, Stop, Seek, end-of-stream, device loss, and shutdown.
- Keep device discovery and stream reconfiguration on non-real-time control threads.
- Ensure processors and device resources are retired safely without blocking the callback.

## Required verification

- Add deterministic unit tests and offline audio tests.
- Review callback-reachable call paths for I/O, allocation, locks, and unbounded work.
- Test device enumeration/open/close and known-signal playback on Windows and macOS.
- Record exact platform, toolchain, audio device, test commands, outcomes, and limitations.

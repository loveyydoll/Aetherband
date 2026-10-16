---
applyTo: "core/**/*.rs, bindings/c_abi/**/*, **/*audio*, **/*decoder*, **/*ringbuf*, **/*device*"
---

# Real-Time Audio, Concurrency and Lifecycle Rules

These constraints override convenience or stylistic preferences whenever code may execute on the audio callback thread.

## Audio callback contract
- Callback execution must be bounded: no unbounded loops, blocking waits, sleep, filesystem/network I/O, logging, synchronous UI dispatch or blocking mutex/RwLock acquisition.
- Avoid heap allocation, deallocation, and arbitrary destructors on the callback. Resource destruction can execute arbitrary code; use a documented ownership-transfer/deferred-reclamation design.
- Do not call potentially blocking decoder operations, device discovery or stream reconfiguration from the callback.
- Handle channel count, sample rate, frame count, buffer capacity, malformed commands and absent tracks explicitly. Define behaviour for zero, mono, stereo, multichannel and oversized buffers.
- Avoid panic paths on callback-reachable code. Do not rely on debug-only assertions as runtime validation.

## Thread and queue contracts
For every cross-thread queue, document:
1. Producer and consumer.
2. Whether it is SPSC/MPSC and why that matches actual ownership.
3. Capacity and backpressure/full-queue behaviour.
4. Ownership of messages/resources on success, rejection and shutdown.
5. How dropped/retired resources are reclaimed away from the callback.
6. How the system behaves when the consumer stops or a worker exits unexpectedly.

Never silently replace a bounded lock-free path with a blocking lock or unbounded queue. Never leak resources as a normal path; if a leak is an emergency last resort to protect callback safety, document it, count/report it off-thread, and test that the condition is unreachable in normal operation.

## Decoder and device lifecycle
- Decoding, seeking, file access and resampling setup belong off the callback.
- Define the protocol for Play, Pause, Stop, Seek, EOF, cancellation, track removal and device switching. Account for buffered stale samples and source-position consistency.
- Worker threads need explicit stop signalling, join/termination strategy, error propagation and resource cleanup.
- Device changes must preserve or deliberately reject session state without leaving UI metadata and engine slots inconsistent.
- Sample-rate-dependent DSP must use the active device configuration and be reconfigured safely.
- Avoid joining a worker from itself or waiting for worker progress while holding resources the worker needs.

## Evidence and tests
- Test queue saturation, command floods, removal/rejection, repeated seek, Stop→Play, EOF, worker shutdown, device failure/switching, zero/multichannel output and oversized buffers.
- A zero-allocation test is useful but does not alone prove absence of blocking, destruction, races, glitches or deadlocks.
- Automated tests and code inspection do not replace a documented manual playback/device-switch/clean-exit check on supported hardware.
- State exactly what has been tested. Never describe real-time safety as guaranteed solely because the design intends it.

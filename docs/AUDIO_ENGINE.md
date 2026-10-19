# Aetherband Audio Engine — Target Contract

**Status:** Requirements for the C++/JUCE target, not a description of a fully implemented engine. The legacy Rust engine is reference material only.

## Architecture boundary

The target runtime is C++ and uses JUCE for device/platform infrastructure. Aetherband owns transport semantics, command scheduling, DSP graph execution, processor lifecycle, routing, parameter/automation timing, and offline rendering. Keep domain logic testable without the UI or a physical device.

## Real-time callback contract

The callback must perform bounded, predictable processing. It must not read/write files, access the network, allocate/deallocate unpredictably, wait on a contended mutex/future/thread, decode media, resample files, compile graphs, create/destroy complex processors, or invoke unbounded logging.

Prepare buffers, decoded media, processor state, and graph snapshots on non-real-time threads. Define safe transfer and retirement rules. Use a bounded command/telemetry mechanism and specify overflow behavior. Do not call a design lock-free or wait-free without verifying implementation and memory ordering.

## Contracts to define

- Sample rate, block size, channel layout, and buffer ownership.
- Device enumeration/open/close, device changes, failure reporting, and shutdown.
- Transport clock, play/stop/seek semantics, and scheduling precision.
- Processor prepare/process/release lifecycle.
- Parameter updates, automation timing, and event/MIDI handling.
- Graph validation, cycles/feedback policy, channel compatibility, and safe graph replacement.
- Offline rendering consistency and output format.
- Latency reporting, underflow/overflow behavior, and diagnostics.

## Testing sequence

1. Deterministic unit tests for buffers, parameters, processors, and graph validation.
2. Offline known-signal/golden-output tests for processing and routing.
3. Callback-path review for allocation/blocking hazards.
4. JUCE device tests: enumerate, open, play known signal, stop, close, repeat.
5. Windows and macOS checks including device errors and clean shutdown.

A successful compile does not prove audio works. Offline tests do not prove physical-device behavior. Record platform support per OS and test type.

See ARCHITECTURE.md, CPP_MIGRATION_PLAN.md, and FEATURE_TRACKER.md.

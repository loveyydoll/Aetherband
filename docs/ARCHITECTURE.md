# Aetherband Architecture

## Status

This document describes the target architecture and migration direction, not a claim that the complete system is already implemented. The new native C++ foundation is at an early stage.

## Target stack

- **Language:** C++20 or newer where supported.
- **Build:** CMake.
- **Desktop framework:** not finalized; JUCE is a leading candidate to validate on Windows and macOS.
- **Audio runtime:** Aetherband-owned C++ modules for device lifecycle, callback processing, transport, scheduling and command/telemetry flow.
- **DSP:** an executing graph with processor lifecycle, routing, parameters and automation contracts.
- **Project model:** versioned sessions, stable identifiers, undo/redo commands and explicit media references.
- **Media:** import/decode, resampling, recording and offline rendering behind testable interfaces.
- **Instruments:** independent processors, including a planned C++ port of HypnoSynth.
- **Optional integrations:** C# or other language components only when a concrete use case justifies a stable boundary and dependency.

Windows and macOS are required target platforms. The existing Rust/Flutter implementation remains available as a reference during migration; it is not the target architecture.

## Module boundaries

1. **Application and UI:** presentation, user interaction, keyboard workflows and view state. UI widgets must not own the audio engine's source of truth.
2. **Project/session model:** tracks, clips, media references, commands, undo/redo and versioned serialization.
3. **Audio runtime:** device lifecycle, transport, real-time callback, scheduling, bounded command queues and telemetry.
4. **DSP:** processors, connections, routing, parameter changes, automation and graph lifecycle.
5. **Media:** background decoding, resampling, recording and offline render/export.
6. **Instruments:** instrument state and processing behind a stable processor contract.
7. **Platform layer:** OS-specific device, file-dialog, packaging and lifecycle code isolated behind interfaces.

The UI framework must not become the application model. Keep the core testable without rendering widgets or requiring a live audio device.

## Real-time safety contract

- Never perform file/network I/O, allocate unpredictably, wait on a contended lock or make blocking calls on the audio callback.
- Prepare and retire processors away from the callback.
- Use bounded, real-time-safe command and telemetry channels.
- Define ownership and lifecycle rules for engine, device and processor objects.
- Specify sample rate, block size, channel layout, latency and error behavior.
- Test DSP deterministically offline, then verify actual device playback and shutdown on each supported platform.

## DSP graph requirements

A node/connection data structure is not sufficient. The graph must execute processing over audio buffers. Its contract should cover:
- node preparation, processing and teardown;
- channel layouts and buffer ownership;
- graph validation and cycle/feedback policy;
- parameter changes and automation timing;
- routing and summing semantics;
- safe graph changes while playback is running;
- deterministic offline rendering and fault handling.

Aetherband should own the graph semantics and processor lifecycle. Reusing compatible, license-appropriate DSP algorithms or infrastructure is acceptable.

## Framework selection

JUCE is a leading candidate because it provides desktop UI and audio-related abstractions in C++, but it is not finalized solely by this document. Before adoption, prove:
- Windows and macOS configure/build/package paths;
- basic device open/close and audio callback behavior;
- keyboard, DPI, window and file-dialog integration;
- dependency licensing compatibility with the project's GPL-3.0-or-later license;
- that application and DSP modules can remain testable and reasonably framework-independent.

## Migration rule

Port behavior, not code mechanically. Audit the Rust implementation and classify every subsystem as implemented, tested, partially implemented or planned. Keep the old implementation until the C++ replacement passes the acceptance criteria in [CPP_MIGRATION_PLAN.md](CPP_MIGRATION_PLAN.md).

See also [Project State](PROJECT_STATE.md), [Feature Tracker](FEATURE_TRACKER.md), and [Engine Foundation Audit](ENGINE_FOUNDATION_AUDIT.md).

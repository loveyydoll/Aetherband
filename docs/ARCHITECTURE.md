# Aetherband Architecture

## Status and authority

This document describes the target architecture, not a claim that every layer exists. The binding framework decision is ADR-008 in DECISIONS.md: native C++ and JUCE. Conflicting old documents describe historical architecture and must not override that decision.

## Committed stack

- Language: C++20 or newer.
- Desktop framework: JUCE.
- Build: CMake.
- Required platforms: Windows and macOS.
- Engine: Aetherband-owned runtime and DSP semantics.
- Legacy reference: Rust engine, C ABI/Dart FFI, Flutter, and Dart.

JUCE provides framework, UI, audio-device, and platform infrastructure. It does not replace the need to design Aetherband's processor graph, transport, project model, session semantics, or rendering rules.

## Logical modules

1. **Application shell and UI:** JUCE windows, menus, keyboard interaction, panels, arrangement/mixer presentation, accessibility, and view state.
2. **Project/session model:** tracks, clips, media references, stable IDs, commands, undo/redo, schema versioning, and dirty-state tracking.
3. **Audio runtime:** device lifecycle, callback processing, transport clock, scheduling, bounded command/telemetry exchange, and error reporting.
4. **DSP graph:** processor interfaces, graph validation/execution, channel layouts, routing, parameters, automation, and safe graph changes.
5. **Media pipeline:** import, background decoding, resampling, recording, waveform analysis, and offline render/export.
6. **Instruments and effects:** independent processors with explicit state, parameter, event/MIDI, and lifecycle contracts. HypnoSynth is planned, not yet a C++ feature.
7. **Platform integration:** OS-specific dialogs, paths, device details, packaging, and lifecycle isolated behind interfaces where useful.
8. **Tests and diagnostics:** deterministic unit/offline tests, integration tests, and logging outside the callback.

The UI must not be the source of truth for project or engine state. Core tests should run without constructing the UI or requiring a physical device.

## Real-time callback contract

The callback must have bounded, predictable work. It must not read/write files, access the network, allocate/deallocate unpredictably, wait on locks/futures/threads, decode media, resample assets, compile graphs, or create/destroy complex processors. Prepare data, buffers, processors, and graph snapshots away from the callback. Define ownership, safe transfer, overflow behavior, and retirement.

Specify sample rate, block size, channel layout, latency, transport timing, error behavior, and device-change behavior. Test deterministic DSP offline before verifying actual hardware.

## DSP graph contract

A graph is functional only when it processes audio buffers. Define processor prepare/process/release lifecycle; channel layouts and buffer ownership; validation, ordering, cycles and feedback policy; routing and summing; parameter and automation timing; safe graph replacement during playback; deterministic offline rendering; and fault handling.

Aetherband owns graph semantics and processor lifecycle. Reuse compatible, license-appropriate DSP algorithms when that avoids needless reinvention.

## JUCE integration rules

- JUCE is committed; do not reopen framework selection without explicit owner direction.
- Keep domain logic and DSP testable without UI widgets.
- Do not assume JUCE abstractions automatically make code real-time safe.
- Record exact JUCE version, modules, build configuration, and licence/distribution implications.
- Verify Windows and macOS separately: configure/build, launch, device enumeration, known-signal playback, repeated start/stop/close, packaging, and clean shutdown.
- Update build instructions only after commands have been verified.

## Migration policy

Port behavior and validated requirements, not source line-for-line. Inventory the legacy implementation and label each behavior implemented, tested, partial, or unknown. Preserve the old implementation until the C++/JUCE replacement passes acceptance criteria. Preserve Git history after retirement.

See PROJECT_STATE.md, FEATURE_TRACKER.md, AUDIO_ENGINE.md, and CPP_MIGRATION_PLAN.md.

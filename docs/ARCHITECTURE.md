# Aetherband Architecture

## Product stack

- **Desktop presentation:** Flutter/Dart.
- **Native engine:** Rust in `core/`.
- **Interop:** versioned C ABI in `bindings/c_abi/`, called through the Dart FFI adapter at `prototypes/aetherband-flutter-ui/lib/src/native_engine.dart`.
- **Audio I/O and decoding:** Rust (`cpal`, `symphonia` and related engine components).

The former C#/.NET + Avalonia frontend is retired and removed from the desktop application. Do not recreate a second desktop UI unless the owner explicitly reverses this decision.

## Boundary rules

1. Flutter owns presentation, user interaction, timeline drawing, window integration and UI state.
2. Rust owns audio I/O, file decoding, mixing, DSP, scheduling and the real-time callback.
3. Dart calls only exported C ABI functions. It must not bind to private Rust symbols or pass continuous audio buffers through widgets, isolates or platform channels.
4. Keep FFI declarations aligned with the actual exported functions and `#[repr(C)]` structs. Validate API version, layout, ownership, null handling and native error codes.
5. Serialize operations on an engine handle. Do not destroy the engine while a native call or telemetry poll is in flight.
6. Native loading, file I/O, waveform generation and project serialization must not block the audio callback. Expensive work must not block Flutter's UI isolate.
7. Never report mock state as real playback, recording, saving, export or plugin execution.

## Data paths

- **Control:** Flutter UI -> Dart FFI -> bounded Rust engine control API -> audio engine.
- **Telemetry:** Rust engine telemetry -> C ABI struct -> Dart polling adapter -> UI state.
- **Audio:** Rust decoder workers -> preallocated/bounded engine buffers -> Rust audio callback -> OS audio device.

The current C ABI exposes engine lifecycle, transport, telemetry, device enumeration/selection, test tone, track load/remove, track gain/pan/mute and track count. Check `bindings/c_abi/src/lib.rs` as the source of truth before adding calls. ABI version 0.2.0 adds `daw_engine_get_sample_rate`, and the Flutter adapter now converts playhead frames using the active output sample rate rather than assuming 48 kHz. Device selection is not yet fully wired into Flutter; if that is added, refresh the cached sample rate after a successful switch.

## Why Flutter

Flutter was selected for its UI flexibility, custom timeline and mixer rendering, faster visual iteration, consistent cross-platform presentation, and ability to optimize rendering for DAW-specific workloads. These are engineering goals, not proof that Flutter is inherently faster than other UI frameworks; profile actual sessions on supported operating systems.

## Verification

From the repository root, run Rust formatting/checks/tests and build the C ABI library. From `prototypes/aetherband-flutter-ui/`, run `flutter pub get`, `flutter analyze`, and `flutter test`. Native loading and real audio playback require manual end-to-end verification on Windows and macOS.

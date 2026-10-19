# Aetherband Architecture

**Current target:** Windows desktop only. See [Technology choices](TECH_STACK.md) for language and platform scope.

## Product stack

- **Desktop presentation:** Flutter/Dart.
- **Native engine:** Rust in `core/`.
- **Interop:** versioned C ABI in `bindings/c_abi/`, called through the Dart FFI adapter at `apps/desktop/lib/src/native_engine.dart`.
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

ABI 0.8.0 exposes engine lifecycle, transport and telemetry; Windows output-device enumeration/selection; HypnoSynth events, editable 16-step sequence and performance settings; track import, metadata, start scheduling, gain, pan, mute and solo; Windows input recording; and offline stereo WAV export. Check `bindings/c_abi/src/lib.rs` as the source of truth before adding calls. The Flutter Audio menu uses the existing device exports on the serialized native worker; after a successful switch, the adapter refreshes the active sample rate used for playhead telemetry.

Native calls run in a long-lived Dart isolate, serialized with polling and disposal. The opaque C handle delegates engine and decoder work to a dedicated Rust control thread through a bounded channel, keeping that work away from Flutter's UI isolate and preserving one serialized engine owner. This remains an architectural choice; the current CPAL 0.18 stream is Send. The control channel is separate from real-time SPSC queues; blocking and allocation remain off the audio callback. See ADR-008 in [Decisions](DECISIONS.md).

## Why Flutter

Flutter was selected for its UI flexibility, custom timeline and mixer rendering, and rapid visual iteration. These are engineering goals, not proof that Flutter is inherently faster than other UI frameworks; profile actual sessions on Windows.

## Verification

From the repository root, run Rust formatting/checks/tests and build the C ABI library. From `apps/desktop/`, run `flutter pub get`, `flutter analyze`, and `flutter test`. Native loading and real audio playback require manual end-to-end verification on Windows.

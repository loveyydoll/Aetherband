# Aetherband Flutter Desktop

This is Aetherband's Windows-only desktop frontend, built with Flutter/Dart. It communicates with the native Rust audio engine through the versioned C ABI using Dart FFI. Other operating systems are deferred by the current project direction.

## Status

Use **Import** in the arrangement toolbar to load audio; known-duration clips can be moved on the beat grid while stopped at the start. The Audio menu lists Windows output devices and switches the engine stream. HypnoSynth plays live keys and its generated phrase. Sessions save and reopen imported tracks and mixer/performance settings. **Export Mixdown** writes stereo PCM16 WAV. Waveforms, recording, editable MIDI regions, split/trim/resize, undo/redo, and effects processing are not implemented yet; errors are shown instead of simulated success.

## Prerequisites

Install the stable Flutter SDK and Windows desktop build tools: https://docs.flutter.dev/platform-integration/desktop

Build the Rust C ABI library from the repository root:

```sh
cargo build -p daw_core_ffi
```

Then from this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Architecture

- `lib/src/aetherband_app.dart`: arrangement-first application and workspace.
- `lib/src/theme.dart`: design tokens and theme.
- `lib/src/models.dart`: timeline presentation models; demo data is not a loaded native session.
- `lib/src/native_engine.dart`: Dart FFI adapter for the C ABI.
- `lib/src/widgets/`: timeline and workspace panels.

All native calls are isolated behind the engine controller. Do not pass audio buffers through widgets or platform channels, and do not run DSP in Dart. The FFI adapter must serialize engine access and destroy native resources only after polling and control calls have stopped.

The app currently targets Windows only. Nonzero samples, output-device selection, pause/restart, import, telemetry, export and clean shutdown have been exercised on the local WASAPI device; physical speaker listening and loopback capture remain unverified.

## Native integration test

The default test suite skips hardware-dependent playback. To exercise the built library on Windows in PowerShell:

```powershell
$env:AETHERBAND_NATIVE_LIBRARY = (Resolve-Path ../../target/debug/daw_core.dll).Path
flutter test test/native_engine_integration_test.dart
```

An available Windows output device is required. The test generates a quiet 44.1 kHz mono WAV with a Unicode path, checks device enumeration and selection, metadata, playback telemetry, Pause/Stop/restart, export, removal/failure handling, backlog limits and queued shutdown. It does not independently record or assess the physical speaker output.

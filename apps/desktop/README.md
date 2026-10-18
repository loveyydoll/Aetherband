# Aetherband Flutter Desktop

This is the target desktop frontend for Aetherband, built with Flutter/Dart. It is intended to communicate with the native Rust audio engine through the existing C ABI using Dart FFI. The Rust engine remains responsible for audio I/O, decoding, mixing, and DSP.

## Status

Use **Import audio** in the arrangement toolbar (or Track → Add Audio Track) to load a file. Import rewinds transport so the source starts at timeline zero. Clips use probed duration; unavailable duration is labelled. Imported audio has no fabricated waveform and cannot be visually moved or mixed until those native workflows are wired. Demo clips and instrument controls remain previews. Engine errors and failed operations are surfaced.

## Prerequisites

Install the stable Flutter SDK and platform build tools:
- Windows: https://docs.flutter.dev/platform-integration/desktop
- macOS: https://docs.flutter.dev/platform-integration/desktop

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

On macOS use `flutter run -d macos`.

## Architecture

- `lib/src/aetherband_app.dart`: arrangement-first application and workspace.
- `lib/src/theme.dart`: design tokens and theme.
- `lib/src/models.dart`: timeline presentation models; demo data is not a loaded native session.
- `lib/src/native_engine.dart`: Dart FFI adapter for the C ABI.
- `lib/src/widgets/`: timeline and workspace panels.

All native calls are isolated behind the engine controller. Do not pass audio buffers through widgets or platform channels, and do not run DSP in Dart. The FFI adapter must serialize engine access and destroy native resources only after polling and control calls have stopped.

The app cannot claim full engine integration until Windows and macOS native loading, real playback, track loading, error paths, and clean shutdown have been exercised.

## Native integration test

The default test suite skips hardware-dependent playback. To exercise the built library on Windows in PowerShell:

```powershell
$env:AETHERBAND_NATIVE_LIBRARY = (Resolve-Path ../../target/debug/daw_core.dll).Path
flutter test test/native_engine_integration_test.dart
```

On macOS, set the same environment variable to an absolute path to `target/debug/libdaw_core.dylib`. An available output device is required. The test generates a quiet 44.1 kHz mono WAV with a Unicode path, checks metadata, playback telemetry, Pause/Stop/restart, removal/failure handling, backlog limits and queued shutdown. It does not independently record or assess the physical speaker output.

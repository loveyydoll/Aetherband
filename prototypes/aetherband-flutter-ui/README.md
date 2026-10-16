# Aetherband Flutter UI prototype

This directory is an isolated Flutter desktop UI prototype. It does not replace
the existing Avalonia application and does not connect to the Rust audio engine.

## Status

- Interactive mock arrangement, track selection, clip selection/movement, zoom,
  browser categories, demo transport, demo meters, device panel and mock mixer.
- All transport, recording and meter behaviour is simulated.
- No audio is generated, recorded, decoded, or sent to hardware.
- Existing Rust, C ABI, C# and Avalonia files are not modified by this prototype.

## Prerequisites

Install the stable Flutter SDK and the platform build tools described in the
official Flutter desktop guide:

- Windows: https://docs.flutter.dev/platform-integration/desktop
- macOS: https://docs.flutter.dev/platform-integration/desktop

## Run

From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

On macOS, use `flutter run -d macos`. Run only a target supported by the
current host and installed toolchain.

## Architecture

- `lib/src/aetherband_app.dart`: app state and layout.
- `lib/src/theme.dart`: design tokens and Flutter theme.
- `lib/src/models.dart`: demo tracks and clips.
- `lib/src/mock_engine.dart`: deliberately simulated transport telemetry.
- `lib/src/widgets/`: timeline, clips, browser and bottom dock.

A future engine integration should use the existing repository's actual C ABI or
a separately reviewed Rust bridge. Do not pass audio buffers through Flutter UI
events, and do not run DSP in Dart.

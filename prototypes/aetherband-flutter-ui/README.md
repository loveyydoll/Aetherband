# Aetherband Flutter Desktop UI — Current Prototype

**Product direction:** This workspace is the starting point for Aetherband's mandatory full-scale Flutter desktop UI. It is not optional unless the owner explicitly changes the decision. See [`docs/FLUTTER_DESKTOP_MIGRATION.md`](../../docs/FLUTTER_DESKTOP_MIGRATION.md) and [`docs/AI_HANDOFF.md`](../../docs/AI_HANDOFF.md).

**Runtime status:** This workspace remains a **UI-only mock**. The Dart FFI adapter and actual connection to the Rust engine have not been implemented. The existing C#/Avalonia app remains the transition audio-connected frontend until Flutter reaches parity and passes the migration gates.

## Present UI

- Compact desktop menu: File, Edit, Track, Region, Navigate, Record, Mix, View, Window, Help.
- Transport/control strip with position, tempo, meter and browser/mixer toggles.
- Arrangement-first multitrack timeline, ruler, demo clips and synthetic waveform illustrations.
- Library/browser categories, instrument/device preview, effect chain, mock mixer and telemetry meters.
- Dark charcoal palette with warm text, sage, magenta and blue accents.
- Widget smoke test intended to catch layout/framework exceptions.

These visible controls do not all represent implemented DAW functions. Transport, clip data/visuals, track control state, recording status, meters, presets, instrument knobs and mixer state are currently local/mock behavior. Do not call them native audio features or present unavailable File/Edit/Track/Region/Mix actions as working functionality.

## Architecture requirements

- Rust remains the audio engine and DSP implementation.
- Flutter must connect through Dart `dart:ffi` to the existing flat C ABI in `bindings/c_abi/src/lib.rs`.
- Do not directly call private Rust internals, port DSP/decoding/device callbacks to Dart, or pass continuous audio buffers through widgets/events.
- `csbindgen` currently generates C# P/Invoke declarations only; Dart requires a separate FFI adapter.
- Use actual exported symbols and matching `#[repr(C)]` layouts from the Rust ABI source. Some older documentation contained aspirational symbols/types that are not current exports; see [`docs/API_CONTRACT.md`](../../docs/API_CONTRACT.md).
- Keep all calls for one engine handle serialized through an owner boundary/isolate until the ABI explicitly proves safe concurrent access. Treat return codes and engine/device errors as actual UI states.
- Keep `MockEngineController` injectable for widget tests, but do not let it silently stand in for the production audio engine.

## Prerequisites

Install Flutter stable and the native desktop tools described in the official [Flutter desktop guide](https://docs.flutter.dev/platform-integration/desktop):

- **Windows:** Visual Studio with the **Desktop development with C++** workload.
- **macOS:** Xcode and command-line tools.

## Run the current UI preview

From the repository root, in PowerShell:

```powershell
cd prototypes\aetherband-flutter-ui
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

On macOS, use `flutter run -d macos`.

If native runner directories are missing, `flutter create --platforms=windows,macos .` can scaffold them in this directory. Review any generated/untracked changes before committing them.

## CI validation

The root workflow `.github/workflows/flutter-ui-prototype.yml` runs on Windows and macOS:
- Generate desktop runners for the host.
- `flutter pub get`.
- `flutter analyze`.
- `flutter test`.
- Build the host's native Flutter desktop target in debug mode.

At the UI refinement handoff, these checks passed on PR-head commit `3bd8e73827dcf628283575872cfa616463779e73` in [run 38982461083](https://github.com/loveyydoll/Aetherband/actions/runs/38982461083). Re-check CI on the current commit before relying on this historical result.

## Next implementation target

Replace the mock engine behind a small, testable engine-client abstraction with a Dart FFI adapter over the C ABI. First connect real engine creation/destruction, API version, output-device enumeration/selection, audio file load/remove, Play/Pause/Stop, per-track volume/pan/mute, master gain and telemetry. Add ABI layout, return-code, lifecycle, missing-library and clean-shutdown tests before enabling native engine integration by default. Then complete the full production UI and feature parity described in the migration guide.

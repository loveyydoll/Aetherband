---
applyTo: "**/*.dart, **/pubspec.yaml, **/analysis_options.yaml"
---

# Flutter / Dart / Dart FFI Instructions — Aetherband

## Product direction

- Flutter is the mandatory full-scale desktop UI target for Aetherband. Do not abandon it or revert the product direction because implementation is difficult unless the owner explicitly changes the decision.
- The current app in `prototypes/aetherband-flutter-ui/` is still a UI mock. Do not describe it as audio-connected.
- Read `AGENTS.md`, `docs/FLUTTER_DESKTOP_MIGRATION.md`, and `docs/AI_HANDOFF.md` before changing Flutter/FFI architecture.

## Native boundary

- The Rust engine and audio/DSP implementation remain in `core/`; Flutter consumes the flat C ABI in `bindings/c_abi/src/lib.rs` via a dedicated Dart FFI layer.
- Do not call Rust internals directly from Dart, move audio DSP/decoding into Dart, or route raw audio buffers through widgets/events/platform channels.
- The current `csbindgen` setup generates C# bindings; it does not generate Dart FFI bindings.
- Bind only functions, structs, layouts, and error codes that exist in the actual Rust C ABI source. Older API docs may contain stale example declarations; reconcile them before use.
- If the engine needs an operation that the ABI lacks, add it to the Rust ABI as a separately reviewed API change and update `docs/API_CONTRACT.md`, the migration guide and tests.
- Serialize calls for a single engine handle through one owner boundary/isolate until native concurrency guarantees are explicitly documented and tested. Never race create/destroy/control/telemetry calls or destroy while calls are in flight.
- Treat native return codes and API-version mismatch as real errors; do not make local Flutter state imply that native audio succeeded.
- Check native handle ownership, strings/UTF-8, integer widths, `#[repr(C)]` layout, alignment, null handling and resource disposal.

## UI/runtime quality

- Keep widget code presentational and state transitions testable. Put engine interactions behind an injectable interface so widget tests can use a fake without claiming mock audio is real.
- Keep file I/O, waveform/peak extraction, asset scans and expensive work off the UI isolate; use a bounded, explicit worker strategy.
- Poll telemetry at a bounded cadence, cancel timers/subscriptions on disposal, and avoid busy loops.
- All unavailable actions must be explicitly disabled or communicate that they are not implemented; never show false success for file saving, recording, export, editing, or playback.
- Preserve the compact DAW/IDE menu, arrangement-first workspace, deeper charcoal palette and existing Aetherband accent colors unless the owner directs a change. Do not restore the oversized brand banner or copy proprietary DAW assets.
- Include realistic viewport/DPI tests and assert that widgets do not emit Flutter layout/framework exceptions. Never remove failing assertions to make CI pass.

## Validation

From `prototypes/aetherband-flutter-ui/` while that remains the source directory:

```sh
flutter pub get
flutter analyze
flutter test
```

Run the native desktop debug build on its host platform. For FFI work, also build the native `daw_core` library and test symbol resolution, version/layout compatibility, return-code mapping, lifecycle/shutdown and relevant engine operations on Windows and macOS.

Report which checks passed, failed, were skipped, or remain unrun. Do not claim native audio works until it has been exercised end-to-end.

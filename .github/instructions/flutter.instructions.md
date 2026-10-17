---
applyTo: "**/*.dart, **/pubspec.yaml, **/analysis_options.yaml"
---

# Flutter / Dart FFI — Aetherband

- Flutter/Dart is the sole intended desktop UI. Do not reintroduce Avalonia or a second desktop frontend without explicit owner approval.
- Read `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, and `bindings/c_abi/src/lib.rs` before changing the UI/native boundary.
- Rust owns audio I/O, decoding, mixing, DSP, and the real-time callback. Dart owns presentation and sends bounded control operations through the exported C ABI.
- Use the shared adapter in `lib/src/native_engine.dart`; do not scatter raw FFI lookups through widgets.
- Bind only real exported functions and exact `#[repr(C)]` layouts. Handle API-version mismatches, null pointers, native errors, UTF-8 and integer widths explicitly.
- Serialize calls for a single engine handle and stop polling before destruction. Never destroy an engine while another call is in flight.
- Do not pass audio buffers through Flutter events/platform channels, and never run DSP or disk I/O on the audio callback.
- Native library loading and engine errors must be visible. Never simulate success for playback, recording, saving, or export.
- Keep timeline painting and meter updates bounded. Virtualize large track lists and profile frame times rather than assuming performance.
- Test realistic DPI/resize layouts, keyboard/mouse behavior, accessibility, lifecycle and error states. Do not remove assertions to make tests pass.
- Run `flutter pub get`, `flutter analyze`, and `flutter test` from the Flutter application directory. Build and exercise the native library on Windows and macOS before claiming end-to-end audio works.

# Aetherband — Current Engineering Status

**Snapshot date:** 2026-10-17  
**Main commit at snapshot:** `66fc6f9a39b283fdcf8dfd6b7279f02a663e0169`  
**Canonical Flutter direction:** [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md)  
**AI handoff:** [`AI_HANDOFF.md`](AI_HANDOFF.md)

> This is a dated snapshot. Re-check current source, PRs, CI and runtime evidence before treating any item as current. The implementation may move after this snapshot.

## 1. Product and architecture status

Aetherband is an early-alpha, desktop-first DAW.

- **Rust audio engine:** `core/` owns DSP, mixer, decoding coordination, device I/O and the real-time audio callback.
- **Native contract:** `bindings/c_abi/src/lib.rs` is the source of truth for exported functions and C-compatible data layouts.
- **Current audio-connected desktop app:** C#/.NET 10 + Avalonia under `apps/desktop/RouletteStudio.Desktop/`; the folder/namespace has a historical name.
- **Mandatory target desktop app:** Flutter/Dart. The owner explicitly decided that Flutter must be implemented full scale and integrated through Dart FFI over the existing C ABI. This is a required product direction, not an optional prototype or redesign.
- **Transition strategy:** keep Avalonia buildable and audio-connected until Flutter has equivalent supported workflows, passing platform builds/tests and owner review. Do not delete it prematurely.
- **Flutter implementation state:** `prototypes/aetherband-flutter-ui/` is still mock-only. It is not yet an audio-connected production app.

## 2. Flutter UI work merged

### PR #9 — initial Flutter workspace

- PR: https://github.com/loveyydoll/Aetherband/pull/9
- Merge commit: `14ce7938a529e83c2a189b3214f5f02a57670f20`
- Added the isolated Flutter desktop workspace, theme, demo track/clip models, mock engine, timeline, browser, device/instrument/mixer dock, widget test, and Windows/macOS CI workflow.
- Rust, C ABI and Avalonia source were not replaced.

### PR #10 — DAW-style UI polish

- PR: https://github.com/loveyydoll/Aetherband/pull/10
- Merge commit: `66fc6f9a39b283fdcf8dfd6b7279f02a663e0169`
- Added a compact DAW/IDE-style menu and transport strip, darkened the surface palette, made arrangement track lanes responsive, corrected the final ruler cell's width to remove a 28-pixel horizontal overflow, and wrapped browser ListTiles in their own transparent `Material` surfaces to prevent Flutter framework assertions.
- Strengthened the widget smoke test to assert no initial layout/framework exceptions.

### Current Flutter source inventory

- `lib/main.dart`: app entry point.
- `lib/src/aetherband_app.dart`: workspace state/layout/menu/transport.
- `lib/src/theme.dart`: theme tokens.
- `lib/src/models.dart`: demo-only track and clip models.
- `lib/src/mock_engine.dart`: fake engine/telemetry; replace behind an injectable engine interface when implementing native FFI.
- `lib/src/widgets/timeline_view.dart`: ruler, track headers/lanes, clip positioning and mock controls.
- `lib/src/widgets/clip_tile.dart`: visual demo clip/waveform illustration, not decoded audio peaks.
- `lib/src/widgets/workspace_panels.dart`: browser, instrument/device preview, knobs, effects and mixer mock UI.
- `test/widget_test.dart`: workspace/menu/transport/layout smoke test.
- `.github/workflows/flutter-ui-prototype.yml`: workflow at repository root for Windows/macOS analysis, tests and host debug builds.

## 3. Visual design contract

The current design uses:

| Token | Value |
|---|---|
| background | `#1B1C20` |
| panel | `#27282D` |
| raised/border | `#35363D` |
| grid | `#2D2E34` |
| warm paper text | `#E9E3D9` |
| secondary text | `#AAA8B0` |
| sage | `#A9B69A` |
| magenta | `#E94E91` |
| blue | `#485CC7` |

The UI direction is an arrangement-first workstation, compact application menus, library/browser sidebar and bottom instrument/mixer dock. Do not restore the oversized product-title banner by default. Preserve original styling and assets; general DAW/IDE workflow conventions are reference material, not code/assets to copy.

## 4. Verified checks — UI PR head

The Flutter CI run [38982461083](https://github.com/loveyydoll/Aetherband/actions/runs/38982461083) completed successfully on PR-head commit `3bd8e73827dcf628283575872cfa616463779e73` before PR #10 was merged:

- Windows: Flutter setup, desktop runner generation, dependency install, `flutter analyze`, `flutter test`, `flutter build windows --debug` — passed.
- macOS: Flutter setup, desktop runner generation, dependency install, `flutter analyze`, `flutter test`, `flutter build macos --debug` — passed.

The merged main commit contains those source changes. Re-check the current post-merge commit before claiming fresh verification on that exact commit. The docs work currently in progress has not run local tests or altered Dart/C/Rust source.

## 5. Known failing or incomplete work

### Rust formatting check

Rust Actions run [38982465835](https://github.com/loveyydoll/Aetherband/actions/runs/38982465835) failed at `cargo fmt --all -- --check`. Rustfmt identified formatting differences in `core/src/lib.rs` around lines 232 and 243. Workspace check and tests were skipped after that failure. The Flutter UI PR did not edit those Rust lines. Fix and re-run this independently; do not suppress the workflow or treat the failure as a Flutter test failure.

### Flutter/native integration — not implemented

- No production Dart FFI adapter exists at this snapshot.
- Flutter has not yet loaded or created a real `DAWEngine` handle.
- Flutter transport, recording state, playhead, meters, track volume/mute/solo, device list, instrument panel and mixer are not wired to native state.
- Timeline clips and waveforms are demo data, not real file-backed audio regions or extracted peaks.
- Native library build/package/search paths are not yet integrated into the Flutter app.
- The menu includes placeholder actions that report they are not connected; these must not be presented as live functionality in a production mode.

### Current ABI/functionality gaps

The C ABI currently exports engine lifecycle, play/pause/stop, master gain/test tone, telemetry poll, device count/info/select, load/remove track, track volume/pan/mute and track count. It does not yet export a complete project/session model, clip editing, seek/scrub, audio recording, MIDI sequencing, plugin/effects chains, automation or export. See [`API_CONTRACT.md`](API_CONTRACT.md) for current exported signatures/fields and limitations.

The current `csbindgen` build generates C# P/Invoke bindings only. Dart must have its own adapter. Do not copy stale `DAWConfig`, `DAWCommand`, `daw_engine_send_command` or similar examples from older drafts without confirming they exist in `bindings/c_abi/src/lib.rs`.

## 6. Next priorities

1. Resolve the Rust formatting CI failure and re-run Rust format/check/tests; preserve all real-time safety guarantees.
2. Implement a testable Dart engine-client abstraction and native FFI adapter over actual C ABI exports.
3. Validate API version, layouts, string marshaling, return codes, library loading, engine creation/destruction and telemetry.
4. Connect existing real capabilities (devices, load/remove track, transport, master/track controls and meters/playhead) with error handling and lifecycle safety.
5. Add integration tests and runtime/manual verification on Windows and macOS with actual audio devices.
6. Continue the full-scale Flutter workstation implementation; add missing C ABI and engine features as required by later product phases.
7. Only then promote Flutter to the default run/package path and retire Avalonia in a separate reviewed change.

## 7. Verification commands

At the Flutter workspace while it remains in the prototype path:

```sh
cd prototypes/aetherband-flutter-ui
flutter pub get
flutter analyze
flutter test
```

On Windows, also run `flutter build windows --debug`; on macOS, `flutter build macos --debug`.

For Rust, from the repository root when native dependencies are available:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

For changes to the actual audio path, automated checks are not sufficient: record the OS, device, sample rate, steps and outcome for playback, Stop → Play restart, track load/remove, device switching and clean shutdown.

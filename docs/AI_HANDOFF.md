# Aetherband — AI Handoff and Work History

**Last updated:** 2026-10-17  
**Current `main` commit at time of update:** `66fc6f9a39b283fdcf8dfd6b7279f02a663e0169`  
**Mandatory direction:** Full-scale Flutter desktop UI, integrated with the existing Rust engine through the C ABI. See [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md).

This is the handoff for a new AI coding session. Read it with [`AGENTS.md`](../AGENTS.md) and the Flutter migration guide before planning work.

## 1. Project facts

- Aetherband is an early-alpha, desktop-first open-source DAW.
- Rust in `core/` owns the audio engine, decoder workers, DSP/mixing, device I/O and audio callback.
- `bindings/c_abi/` exports the native interface. This is the required Flutter/native boundary.
- The currently existing audio-connected desktop app is C#/.NET 10 + Avalonia under `apps/desktop/RouletteStudio.Desktop/` (the folder/namespace has a historical name). Keep it while Flutter parity is built and verified.
- Flutter/Dart is the mandatory long-term desktop frontend, not an optional experiment. Do not reverse this decision unless the owner explicitly does so.
- Flutter UI code currently lives under `prototypes/aetherband-flutter-ui/`, which is intentionally isolated from the old UI. It is visual/mock-only at present, so do not claim it can play audio.

## 2. Decision summary — do not regress

1. Flutter is the target desktop UI and must be implemented at full scale.
2. Flutter talks to Rust only through a thin Dart FFI adapter over the C ABI (or a reviewed thin bridge that preserves the C ABI boundary).
3. Rust remains the audio/DSP engine. Never move DSP, file decoding, or the hardware audio callback into Dart.
4. Keep Avalonia buildable until real feature parity and the migration acceptance checks are met. It is a temporary safety net, not the intended final frontend.
5. Staged work and quality gates remain mandatory: do not call mock functionality complete, skip tests, weaken assertions, or bypass real-time/ABI safety in the name of progress.

## 3. Work performed and merged

### Flutter UI concept — PR #9

PR: https://github.com/loveyydoll/Aetherband/pull/9  
Merged base commit: `14ce7938a529e83c2a189b3214f5f02a57670f20`

Introduced the isolated Flutter app under `prototypes/aetherband-flutter-ui/`, including:
- Flutter app scaffold, theme and mock/demo models.
- An arrangement timeline with demo tracks, color-coded clips and drawn synthetic waveforms.
- Library browser, instrument/device dock, knobs, effects chain and mock mixer/meters.
- Simulated engine controller and a widget smoke test.
- GitHub Actions workflow for Flutter analyze/test and Windows/macOS debug builds.

The prototype deliberately did **not** change the Rust core, C ABI, generated C# bindings, or the Avalonia UI. All engine/transport/meter/device data in the prototype is fake/local.

### DAW-style layout refinements — PR #10

PR: https://github.com/loveyydoll/Aetherband/pull/10  
Merged commit: `66fc6f9a39b283fdcf8dfd6b7279f02a663e0169`  
Validated PR-head commit: `3bd8e73827dcf628283575872cfa616463779e73`

Changes made:
- Added a compact menu row: File, Edit, Track, Region, Navigate, Record, Mix, View, Window, Help.
- Added a dedicated transport/control row with position, tempo, time signature, browser and mixer toggles.
- Removed the oversized demo branding badge and reduced repetitive status text.
- Darkened the palette while keeping signature accents.
- Made timeline lane heights respond to available vertical space and tightened track-header volume controls.
- Fixed a ruler overflow caused by rounding up bar count and giving the final ruler cell a full bar width; the last cell now uses only the remaining width.
- Fixed Flutter test assertions from BrowserPanel ListTiles by wrapping each one in its own transparent `Material`, so background decorations do not mask ListTile ink.
- Tightened the widget smoke test to assert no initial layout/framework exception and check the new menu.
- Kept the change UI-only; it did not modify Rust audio code.

## 4. Current visual tokens

From `prototypes/aetherband-flutter-ui/lib/src/theme.dart`:

| Token | Value |
|---|---|
| background | `#1B1C20` |
| panel | `#27282D` |
| raised | `#35363D` |
| grid | `#2D2E34` |
| paper text | `#E9E3D9` |
| secondary text | `#AAA8B0` |
| sage accent | `#A9B69A` |
| magenta active/record accent | `#E94E91` |
| blue/modulation accent | `#485CC7` |

UI direction: compact and information-dense like a workstation/IDE; arrangement first, browser to the left, device/mixer dock below, quiet dark borders and original visual styling. Do not return to a large name banner. Do not copy proprietary DAW artwork or distinctive assets.

## 5. Exact current implementation state

| Area | State |
|---|---|
| Flutter workspace | Merged and build/test validated |
| Menu bar and transport UI | Present; several commands intentionally display “not connected” notices |
| Timeline/clip visualization | Mock/demo model; synthetic clip waveform illustration, not file-derived audio peaks |
| Playback/record button state | Simulated; not real audio playback or recording |
| Track volume/mute/solo | Prototype state only; no Rust engine call yet |
| Device/effect/instrument panels | UI preview only |
| Mixer meters and playhead | Mock telemetry only |
| Dart FFI adapter | Not implemented |
| Native library loading/package | Not implemented for Flutter |
| Real audio workflow in Flutter | Not implemented |
| Existing C# / Avalonia app | Preserved; this remains the legacy audio-connected frontend |

Do not mark a UI component “implemented” as an engine feature until it is connected to the native API and has a meaningful test.

## 6. Actual C ABI boundary

Current source of truth: `bindings/c_abi/src/lib.rs`. At the handoff snapshot, these are the listed exports:

```text
daw_get_api_version
daw_engine_create
daw_engine_destroy
daw_engine_play
daw_engine_pause
daw_engine_stop
daw_engine_set_master_volume
daw_engine_set_test_tone
daw_engine_poll_telemetry
daw_engine_get_device_count
daw_engine_get_device_info
daw_engine_select_device
daw_engine_load_track
daw_engine_remove_track
daw_engine_set_track_volume
daw_engine_set_track_pan
daw_engine_mute_track
daw_engine_get_track_count
```

ABI version reports 0.1.0. The actual `#[repr(C)]` field layouts and per-function return codes in `src/lib.rs` override any older documentation. Older `API_CONTRACT.md` text previously contained example symbols such as `daw_engine_send_command` and structs like `DAWCommand` that were not in the source exports; do not copy those outdated examples. The migration guide has the current detailed plan, and this documentation pass is reconciling the contract.

Important: `csbindgen` currently generates C# P/Invoke declarations. It does not create Dart FFI declarations. Flutter needs its own well-tested `dart:ffi` adapter with compatible struct layouts and native library packaging. Keep calls for one engine handle serialized through one owner boundary/isolate until the ABI explicitly defines and proves safe concurrency; do not call create/destroy/control/poll concurrently from separate Dart isolates.

## 7. Verification history and remaining red check

Flutter CI run [38982461083](https://github.com/loveyydoll/Aetherband/actions/runs/38982461083), on PR-head commit `3bd8e73827dcf628283575872cfa616463779e73`, completed with success. Windows and macOS each completed:
- Flutter SDK setup and desktop runner generation.
- `flutter pub get`.
- `flutter analyze`.
- `flutter test`.
- The host platform's debug desktop build (`flutter build windows --debug` on Windows and `flutter build macos --debug` on macOS).

PR #10 was then merged into `main` at `66fc6f9a39b283fdcf8dfd6b7279f02a663e0169`. The successful CI evidence is for the PR-head commit immediately before merge; re-check fresh CI before citing current status.

The Rust workflow at run [38982465835](https://github.com/loveyydoll/Aetherband/actions/runs/38982465835) failed at `cargo fmt --all -- --check`. Rustfmt reported formatting differences in `core/src/lib.rs` around lines 232 and 243. Workspace check and tests were skipped after that failure. Flutter PR did not edit those Rust lines. Investigate and fix the Rust formatting on a focused change; do not hide, ignore, or attribute the failure to the Flutter UI patch.

During refinement, widget tests caught and drove fixes for:
- A horizontal `RenderFlex` overflow by 28 pixels in `_TimelineRuler`.
- A ListTile framework assertion caused by placing ListTile ink/background effects behind a decorated ancestor.
These fixes are included in the validated PR-head commit.

## 8. Safe commands for a Windows developer

From a clean checkout, switch to main to get the merged UI code:

```powershell
git switch main
git pull origin main
cd prototypes\aetherband-flutter-ui
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Prerequisite: Visual Studio's **Desktop development with C++** workload. For a macOS build, use Xcode and `flutter run -d macos`.

`flutter create --platforms=windows,macos .` generates local Windows/macOS runner files and is run in CI. Review generated/untracked files before committing them. The current run command launches the **mock-only Flutter prototype**, not an audio-connected production DAW.

## 9. Next engineering priorities

1. Update/keep this handoff, `AGENTS.md`, README, architecture, stack, roadmap, API contract, status and changelog aligned with the mandatory Flutter decision.
2. Fix the independent Rust formatting failure and re-run workspace check/tests.
3. Define the production app packaging/location strategy for Flutter without prematurely deleting Avalonia.
4. Implement the Dart FFI adapter on the actual C ABI; add ABI-layout, error-code, lifecycle and telemetry tests.
5. Connect the existing real engine operations (device discovery, load/remove audio track, transport, track volume/pan/mute, master volume and telemetry) and replace mock state for production.
6. Implement full-scale arrangement/editor workflows and future engine features through reviewed C ABI additions.
7. Make Flutter the default documented frontend only after the migration gates pass; retire Avalonia separately after feature parity and owner review.

## 10. Files agents should read first

- [`AGENTS.md`](../AGENTS.md) — non-negotiable repo/agent rules.
- [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md) — mandatory target architecture, staged plan and acceptance criteria.
- [`ENGINEERING_STATUS.md`](ENGINEERING_STATUS.md) — current engineering snapshot.
- [`API_CONTRACT.md`](API_CONTRACT.md) — current C ABI inventory/layouts.
- [`ARCHITECTURE.md`](ARCHITECTURE.md), [`TECH_STACK.md`](TECH_STACK.md), [`ROADMAP.md`](ROADMAP.md), [`DECISIONS.md`](DECISIONS.md) — architecture/decision history.
- [`AI_WORKFLOW.md`](AI_WORKFLOW.md) and [Flutter instructions](../.github/instructions/flutter.instructions.md) — safeguards.

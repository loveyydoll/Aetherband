# Aetherband Technology Stack

**Reviewed:** 2026-10-17  
**Decision:** Flutter/Dart is the mandatory full-scale target desktop UI. The existing C#/Avalonia application is retained as a transitional audio-connected frontend until migration parity is proven.

## 1. Selected architecture

| Layer | Technology | Current role and constraints |
|---|---|---|
| **Audio engine / DSP** | Rust, 2021 edition, stable | Owns the real-time audio callback, mixer, decoding coordination, device I/O and DSP. Remains the engine; do not rewrite this in Dart. |
| **Audio I/O** | `cpal` | Opens platform-native audio streams; existing native paths handle device audio. |
| **Concurrency** | `rtrb` and bounded native protocols | Audio/control communication. Preserve ownership, queue-capacity and real-time constraints. |
| **Audio decoding** | `symphonia` | WAV playback is reported tested; FLAC, MP3, OGG and AAC/M4A remain unverified end-to-end unless new evidence is recorded. |
| **Resampling** | `rubato` | Native sample-rate conversion. |
| **Native API** | Flat C ABI at `bindings/c_abi/src/lib.rs` | Cross-language boundary used by both the existing C# frontend and the target Flutter frontend. It exposes an opaque `DAWEngine` handle and C-compatible structs. |
| **Target desktop UI** | **Flutter + Dart** | Mandatory implementation target for Windows/macOS. Current source is under `prototypes/aetherband-flutter-ui/`; current app remains mock-only. |
| **Flutter ↔ Rust** | Dart `dart:ffi` wrapper over C ABI | Not yet implemented at the current handoff snapshot. Must check native results, structure layouts, ownership, lifecycle and platform library loading. |
| **Transition desktop UI** | C# / .NET 10 + Avalonia | Existing audio-connected app under `apps/desktop/RouletteStudio.Desktop/`. Expected to be retired after Flutter has verified feature parity; do not delete before the release gates. |
| **Legacy C# bindings** | `csbindgen` | `bindings/c_abi/build.rs` currently generates C# P/Invoke declarations for Avalonia. This does **not** generate Dart bindings and is likely removable with the legacy UI after migration. |
| **Toolchains** | Cargo, Flutter stable/Dart, Visual Studio C++ workload (Windows), Xcode (macOS) | CI and local instructions must validate each host's actual prerequisites. |

## 2. Binding requirements for Flutter

Flutter must connect to the **existing C ABI**, not Rust internals. The exported API inventory in [`API_CONTRACT.md`](API_CONTRACT.md) must be verified against `bindings/c_abi/src/lib.rs` before binding work.

- Use a dedicated, small Dart FFI adapter. Widgets must depend on an injectable engine interface, not raw pointers or static native calls.
- Use only real exports and exact `#[repr(C)]` layouts. Older examples in stale docs may mention symbols/structs that do not currently exist; never copy them blindly.
- Consider a canonical C header and Dart binding generation as part of integration after checking available tooling/dependencies. `csbindgen` is C#-specific in the current repository.
- Until concurrency guarantees are explicitly established, serialize calls for one `DAWEngine` handle through a single owner boundary/isolate. Prevent concurrent lifecycle/control/telemetry calls and never destroy the handle with calls in flight.
- Check API version and all return codes. Communicate engine/device failures to the UI; do not make local transport state look like engine success.
- Keep audio buffers, decoding, DSP and device callbacks inside Rust. No raw audio buffers through widget events or a Dart-side audio callback.
- Update API documentation and tests for every exported API change.

## 3. Flutter desktop UI status

Merged source includes:
- A compact workstation menu bar (File, Edit, Track, Region, Navigate, Record, Mix, View, Window, Help).
- A transport strip and arrangement-first work area.
- A library browser and bottom instrument/mixer preview dock.
- Dark charcoal/sage/magenta/blue styling and synthetic demo clip visuals.
- A widget smoke test and a Windows/macOS CI matrix for analysis, tests and debug builds.

These are presentation features only until connected to real application state and the Rust C ABI. The current `MockEngineController` simulates transport telemetry. It must not silently remain the production engine adapter.

## 4. Target visual tokens

Tokens currently in `prototypes/aetherband-flutter-ui/lib/src/theme.dart`:

| Token | Value |
|---|---|
| Main background | `#1B1C20` |
| Panel | `#27282D` |
| Raised surface / border | `#35363D` |
| Grid | `#2D2E34` |
| Main text, warm paper | `#E9E3D9` |
| Secondary text | `#AAA8B0` |
| Sage accent | `#A9B69A` |
| Active / recording magenta | `#E94E91` |
| Modulation / experimental blue | `#485CC7` |

Maintain a professional, compact, arrangement-first DAW workspace with a lightweight application menu. The design can be refined, but do not revert to oversized branding or copy proprietary DAW code/assets.

## 5. Alternatives and decisions

- **C++ / JUCE engine rewrite:** not selected. Rust and the current C ABI remain the engine architecture.
- **Dart implementation of the audio engine:** not allowed. Dart is the UI and control/client side; real-time audio and DSP stay in Rust.
- **Keeping Avalonia as the permanent main UI:** superseded by the owner's explicit Flutter decision. Keep Avalonia during migration only for parity, comparison and recovery.
- **Using existing C# P/Invoke bindings from Dart:** not possible directly. Flutter needs Dart FFI declarations for the same native C ABI.
- **Dropping the C ABI to use a private bridge:** not allowed without explicit owner approval and a separately reviewed architecture decision. New needed operations should be surfaced as stable C ABI exports.

See [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md), [`DECISIONS.md`](DECISIONS.md) (ADR-008), and [`AI_HANDOFF.md`](AI_HANDOFF.md) for implementation stages and history.

## C# retirement decision

**Likely final state:** C# / Avalonia and its C#-specific binding-generation path will be removed from the shipped product and likely from the repository after Flutter reaches verified parity. A permanent dual-frontend arrangement is not the default plan.

This is not an immediate deletion task. Keep the existing app buildable until:
- Flutter uses the real C ABI and covers every currently supported audio-connected workflow.
- Windows and macOS audio, device switching, transport, track controls, telemetry, errors and shutdown are tested.
- Flutter becomes the default documented build/run and CI/release path.
- The owner reviews and approves the parity evidence.

Then remove the Avalonia project, C#-only generated binding wiring, .NET-only CI and obsolete scripts in a separate reviewed change. Keep Rust, the C ABI, the canonical C header, Dart FFI and native ABI tests. Search every build script, workflow, docs link and release process before removal.

## 6. Migration acceptance gates

Flutter becomes the default documented desktop app only after it:
1. Loads the native `daw_core` library reliably on Windows and macOS.
2. Uses real native engine results for current engine-supported workflows (device enumeration/selection, load/remove audio tracks, transport, track/master controls and telemetry).
3. Has no false-success controls or mock engine fallback in production mode.
4. Passes Dart analysis, widget/integration tests, native build and ABI lifecycle/layout checks in both platform CI jobs.
5. Reaches user-reviewed feature parity with the currently audio-connected Avalonia frontend.
6. Has reproducible packaging, run instructions, useful startup/engine errors and documented remaining limitations.

The full-scale Flutter direction is mandatory; these gates govern a safe migration, not whether migration is pursued.

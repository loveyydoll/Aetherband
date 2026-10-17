# Engine Foundation Audit

**Audit date:** 2026-10-17  
**Baseline:** `main` at the time this audit branch was created  
**Status:** Source review only; no local Windows/macOS runtime or audio-device test was performed.

This document records observed implementation and the next engineering sequence. It is not a claim that real hardware playback has been verified.

## Executive finding

Aetherband does **not** need a blind, from-scratch rewrite. The repository already contains a meaningful Rust audio pipeline: CPAL output, a callback processor, bounded command/telemetry queues, background Symphonia decoding, Rubato resampling, track mixing, a versioned C ABI, and a Dart FFI controller. The right first move is to harden and prove this foundation, replacing components where tests or code review demonstrate a specific defect.

The current gap is less “there is no engine” and more “the engine/UI contract and end-to-end workflow are not yet demonstrated as dependable.”

## Observed architecture

- `core/src/device.rs`: CPAL output stream creation and device enumeration.
- `core/src/audio.rs`: callback mixing, transport commands, output conversion and telemetry.
- `core/src/decoder.rs`: background decode workers and sample-rate conversion.
- `core/src/ringbuf.rs` / `core/src/track.rs`: bounded queues and track playback state.
- `core/src/lib.rs`: control-thread engine lifecycle, track loading/removal, device selection and transport.
- `bindings/c_abi/src/lib.rs`: opaque engine handle, versioned C ABI, transport, telemetry, device and track exports.
- `prototypes/aetherband-flutter-ui/lib/src/native_engine.dart`: ABI version check, library loading, engine lifecycle, Play/Pause/Stop and telemetry polling.
- `prototypes/aetherband-flutter-ui/lib/src/aetherband_app.dart`: primary Flutter UI, still visibly labels itself `UI PREVIEW` and describes demo clips in its status area.
- `.github/workflows/flutter-ui-prototype.yml`: Windows/macOS Flutter validation still targets the legacy directory path.

## Findings and risks

### 1. Native playback path exists, but hardware behavior is not proven

The engine opens the default CPAL output stream during `DAWEngine::new`. The callback writes interleaved output and is covered by a no-allocation test. This is a useful foundation, but CI compilation and callback unit tests do not prove that a packaged Flutter app loads the right native library or produces audio on a real Windows/macOS device.

**Required evidence:** run the built desktop app, verify the selected output device/sample rate, load a real audio file, hear it, and verify Pause/Stop/rewind and clean shutdown.

### 2. Stop has regression coverage that must be preserved

The existing `stop_silences_output_and_resets_playhead` test checks that Stop silences callback output and reports a stopped transport with a zero playhead. The control thread separately restarts decoder workers. Keep this test and add coverage for Pause/resume, repeated Stop, and command-queue failure paths before changing transport internals.

### 3. FFI is currently narrower than the native API

The C ABI exports device selection and track loading/removal/mix controls. The current Dart `NativeEngineController` resolves only create, play, pause, stop, destroy, telemetry polling and sample-rate query. The UI-facing `EngineController` interface likewise exposes only transport and disposal. Therefore native track/device capabilities are not yet a complete Flutter workflow.

**Next action:** define typed Dart bindings for the existing exports and their result semantics, then expose a small real audio-import/playback path. Do not add UI controls until each operation is connected to native state and reports errors truthfully.

### 4. Device switching can discard the active playback graph

In `DAWEngine::select_device`, the current stream is dropped and a fresh queue/processor is created. The control-thread track metadata and decoder map remain, but the newly created processor starts with an empty track table. Unless the tracks are deliberately reinstalled, changing devices can leave metadata claiming tracks exist while the new callback has no corresponding players.

**Required fix before presenting device switching as dependable:** define a control-thread-safe stream/graph rebuild that recreates the output stream and re-installs track players/decoder consumers while preserving IDs, gain, pan, mute and transport semantics—or explicitly disable device switching until that is implemented and tested. Do not simply recreate queues and silently lose the graph.

### 5. Callback ownership and realtime constraints need targeted review

The callback has bounded command processing and preallocated scratch buffers. It also reconstructs boxed track/consumer pointers received through the command queue. The code comments intend to avoid deallocation in the callback, but every rejection/removal path must be checked for destructor execution, ownership correctness and bounded work. Keep file I/O, decoder joins, resampling setup, device enumeration and UI calls off the callback.

### 6. UI still presents a demo-oriented surface

The Flutter app has a native lifecycle/telemetry path but also contains illustrative clips and preview labels. Do not infer that demo clips are loaded native tracks. The next UI increment should be deliberately small: import a real file, display the native track, play/pause/stop it, and surface failures.

### 7. The app path is still legacy organization

Flutter is documented as the primary desktop UI, but the app remains under `prototypes/aetherband-flutter-ui/`, and CI uses that path. Restructuring it to `apps/desktop/` is reasonable, but should be a separate migration with every workflow, script, instruction, import, generated runner and document reference updated together. It must not be mixed into an unreviewable engine rewrite.

## Recommended implementation order

### Phase A — prove and align the current contract

1. Preserve the Stop regression test and add transport-state tests.
2. Audit C ABI exports against Dart FFI declarations and the API contract.
3. Add ABI layout/version tests and consistent documented return codes.
4. Build and run the Flutter/native app on Windows; repeat on macOS when available.
5. Record exact test commands/results and distinguish CI evidence from hardware evidence.

### Phase B — real audio transport and track workflow

1. Bind existing native track load/remove/count functions through Dart FFI.
2. Add a small import action that passes UTF-8 paths safely and reports native errors.
3. Display tracks from native/session state rather than demo-only presentation models.
4. Verify real file playback, Pause/resume, Stop/rewind, removal, invalid media and clean shutdown.
5. Fix device-switch graph preservation before advertising device switching as reliable.

### Phase C — durable session model and output

1. Introduce stable session/track/clip IDs separate from runtime decoder/player objects.
2. Save/reopen a minimal versioned project without serializing native pointers.
3. Add deterministic offline/stereo WAV export once project scheduling and sample-rate semantics are explicit.

### Phase D — larger engine architecture

Only after the vertical slice works, evolve the engine toward a reusable graph runtime:
- Separate project/session state from compiled runtime graph.
- Typed ports for audio, control, events and analysis.
- Validate and compile graphs on a non-realtime thread.
- Swap prepared graph state through bounded, ownership-safe handoff.
- Keep all callback work bounded and allocation-free.
- Version the graph/patch format and define migration rules.
- Reuse the graph core later for a separate Aether Patcher application.

Do not implement a large node graph, plugin host, granular/spectral engine, MIDI sequencer and spatial renderer in the same change as transport repair. They depend on the reliability and ownership guarantees established here.

## Exit criteria for the first implementation milestone

- Rust formatting, workspace checks and tests pass.
- ABI exports and Dart declarations are reviewed together; version mismatch fails safely.
- Flutter can import and play a real supported audio file through the native engine.
- Play/Pause/Stop/rewind and track removal have regression coverage.
- Failures are surfaced rather than presented as success.
- No claim of real-device verification without a manual Windows/macOS test record.

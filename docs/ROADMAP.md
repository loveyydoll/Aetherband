# Aetherband Development Roadmap

**Project status (2026-10-16): Early alpha — stabilization and verification gate.**

This roadmap describes the implemented baseline and the order of work from here. A feature is not considered complete merely because it compiles: playback behavior, lifecycle handling, automated regression coverage, and runtime verification must also be demonstrated.

## Current state

- [x] Rust audio engine and CPAL output stream.
- [x] C-ABI boundary and generated C# P/Invoke bindings.
- [x] Avalonia desktop shell on .NET 10.
- [x] Background decoding/streaming for WAV, FLAC, MP3, OGG and AAC/M4A (subject to decoder support).
- [x] Multi-track mixing controls: volume, pan, mute and remove.
- [x] Master gain and stereo peak/RMS telemetry.
- [x] Device enumeration/selection UI and Windows build/run scripts.
- [x] Rust CI formatting, workspace check and test workflow; user-reported local verification script passed.
- [ ] **Stabilization gate:** resolve and regression-test the reported Stop behavior (the UI playhead resets, but audio reportedly continues), then verify Play/Pause/Stop and track lifecycle end-to-end.
- [ ] Audit decoder/track reset and restart semantics, queue saturation, device switching, end-of-file, and shutdown.
- [ ] Align all docs and acceptance criteria with the implementation; this documentation pass is in progress.

## Phase 1 — Real-time audio foundation

**Status: Implemented; continue regression verification.**

Implemented: CPAL output, callback-driven processing, bounded command handling, SPSC queues, master gain smoothing, stereo metering, and an allocation-safety test harness.

Exit gate: formatting, workspace checks, all tests, and the real-time allocation test pass. Runtime verification must confirm silence while stopped, no callback allocation, and clean shutdown on supported hardware.

## Phase 2 — File playback and native/managed integration

**Status: Implemented; runtime stabilization remains open.**

Implemented: Rust decoder workers, sample-rate conversion, track playback, C-ABI exports, generated C# bindings, and .NET/Avalonia integration.

Exit gate:
- Import supported files and play multiple tracks together.
- Stop immediately silences all tracks and resets the playhead; Play after Stop restarts from the beginning.
- Pause halts output without rewinding; Play resumes according to the documented transport behavior.
- End-of-file, remove-track, repeated stop, and app shutdown are safe.
- Device selection does not leave stale streams or invalid telemetry.

## Phase 3 — Arranger and track controls

**Status: Core UI implemented; acceptance verification remains open.**

Implemented: timeline/track presentation, playhead/timer, track volume, pan, mute, remove, master volume and meters.

Still to verify/improve: visible waveform peaks, accurate playhead timing for non-48-kHz devices, scrub/seek semantics, and consistent UI state when native command submission fails.

## Phase 3.5 — Stabilization gate (current priority)

Do not start new major audio features until this gate is green.

1. Reproduce the Stop bug with the diagnostic test tone disabled and with one imported track.
2. Add a Rust regression test that issues Play, confirms non-silent output, issues Stop, and confirms subsequent output is silent and telemetry reports stopped/playhead zero.
3. Inspect native command return codes and ensure the UI does not claim a command succeeded when the command queue rejects it.
4. Confirm the audio callback consumes Stop and resets track cursors without blocking or allocating.
5. Test Stop while playing, while paused, at EOF, immediately after Play, with multiple tracks, and repeatedly.
6. Test Play after Stop. Decoder streaming must restart or rewind correctly; draining a ring buffer alone does not rewind a decoder worker.
7. Run `cargo fmt --all -- --check`, `cargo check --workspace --all-targets`, `cargo test --workspace --all-targets`, the repository verification script, and the .NET build/tests.
8. Repeat runtime checks on Windows; record platform-specific results rather than implying untested macOS support.

**Acceptance:** Stop is silent and repeatable, playhead resets from authoritative telemetry, Play restarts correctly, and all automated checks pass.

## Phase 4 — Recording, project persistence and export

**Status: Planned.**

- Audio input capture and background file writer.
- Save/load projects and asset management.
- Waveform peak generation and caching.
- Offline WAV bounce/export.
- Autosave and recovery after the core lifecycle is stable.

## Phase 5 — MIDI and instruments

**Status: Planned.**

- MIDI event model and piano roll.
- Built-in instruments and drum sampler.
- Instrument/effect graph and internal DSP.
- MIDI keyboard input and timing tests.

## Phase 6 — Effects, routing and plugin hosting

**Status: Planned; sequence may be refined as architecture matures.**

- Mixer buses, sends/returns and automation.
- Built-in EQ, compression, delay and reverb.
- Plugin architecture, prioritizing an open format before adding other formats.
- Crash isolation and plugin compatibility testing.

## UI revamp sequencing

A visual redesign is welcome after the core transport and engine APIs stop changing. Keep it scoped to presentation and interaction, and do not let it delay the stabilization gate or change audio-thread safety guarantees.

## Definition of done

Every milestone needs: implementation, tests, docs updated in the same change, successful relevant CI, and explicit runtime verification where hardware or UI behavior is involved. Mark unknowns as unknown; never promote planned or partially verified work to complete.

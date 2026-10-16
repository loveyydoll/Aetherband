# Aetherband — Engineering Status Snapshot

**Snapshot date:** 2026-10-16  
**Branch context:** `fix/audio-engine-correctness`, draft PR #1  
**Important:** This is a historical status snapshot, not proof that code compiles or behaves correctly. Re-check source, CI and PR status before acting on it.

## Current stabilization pass — 2026-10-16

Draft PR #3: https://github.com/loveyydoll/Aetherband/pull/3

- Added a terminal zero-frame decoder marker for media whose decoded frame count ends exactly on a full block boundary, plus a track-level regression test for consuming that marker.
- Added local verification scripts for Windows PowerShell and Bash.
- Updated .NET CI to target the desktop project's actual `.csproj` and its `.NET 10` target framework.
- Applied the formatting changes reported by the first Rust CI run.

**Verification remains incomplete:** the first Rust CI run failed during `cargo fmt --all -- --check`, so compile/tests were skipped. Formatting edits were pushed afterward, but no successful rerun has yet been confirmed. The repository has not been built locally in this environment. Do not merge the draft until the latest branch has passing CI and the remaining P0/P1 issues below are resolved or explicitly accepted.

## Project and priority
Aetherband is an early-alpha desktop audio workstation built around a Rust audio engine, C ABI in `bindings/c_abi/`, and a C#/.NET Avalonia desktop application. Current priority is audio correctness, ownership/lifecycle safety, repeatable CI and trustworthy documentation.

## Implementation attempts on PR #1
The following changes were committed to `fix/audio-engine-correctness` and require critical review:
- Bound audio command processing to at most 128 commands per callback.
- Added reverse SPSC retirement communication and fixed-capacity deferred storage intended to move track-player reclamation to the control thread.
- Kept track players boxed in audio track slots.
- Guarded zero-channel output and cleared output channels beyond stereo.
- Initialized the processor using the selected output device's reported default sample rate.
- Added decoder worker join handles and stop/join behavior.
- Added regression tests for zero-channel and extra-channel output.
- Added a Rust CI workflow for formatting, workspace compilation and tests.

These are implementation attempts, not verified fixes. In particular, review all queue-full/rejection paths, callback destruction/deallocation, worker shutdown and decoder/device lifecycle.

## Verification status at snapshot time
- Local Rust checks were not run by the authoring agent.
- The first Rust Actions run failed at `cargo fmt --all -- --check`; compilation and tests were skipped.
- Recent .NET workflow runs on `main` were also failing at that time; inspect their logs before attributing the cause.
- Runtime audio/device checks were not performed.
- PR #1 was a draft and not ready to merge.

References:
- [Draft PR #1](https://github.com/loveyydoll/Aetherband/pull/1)
- [Rust workflow](https://github.com/loveyydoll/Aetherband/actions/workflows/rust.yml)

## Outstanding risks

### P0 — Transport and decoder coordination
- Stop does not yet have a proven protocol for resetting/restarting decoder source position.
- Seek must coordinate the playhead, decoder seek, buffered-audio invalidation and resumption.
- Add tests for Stop → Play, seeking while playing/stopped, repeated seeks, EOF and decoder backpressure.

### P0 — Device switching and active tracks
- Recreating the processor may discard active track slots while control-side metadata/decoder handles remain.
- Device switching must preserve/rebuild track players safely or fail without corrupting the session.
- Test switching with zero, one and multiple tracks, including device-open failure.

### P1 — Real-time safety
- Review AddTrack rejection, RemoveTrack, command floods, queue-full behaviour, processor drop and engine shutdown.
- Prove no destructor/deallocation, logging, blocking wait, I/O, lock or unbounded loop can occur in the callback.
- Add lifecycle-focused safety tests, not just test-tone/allocation tests.
- Define and test the policy for callback buffers above the 2048-frame scratch-buffer cap.

### P1 — Decoder errors and shutdown
- Worker failures need structured error delivery to the engine/UI.
- Verify stop/join cannot hang and workers terminate on track removal and engine shutdown.
- Test corrupt/unsupported media, early EOF, full decoder ring buffer and rapid load/remove.

### P1 — Sample rate, output and device tests
- Validate default and explicitly selected sample-rate initialization.
- Test mono, stereo, multichannel, zero-channel defensive behaviour and oversized buffers.
- Ensure device reconfiguration does not leave UI and processor state contradictory.

### P2 — Repository coherence
- Reconcile stale `CustomDAW` / `RouletteStudio` names and old paths in README, vision, roadmap, workflow docs and solution references.
- Keep this file as a dated engineering snapshot; use `AGENTS.md` for stable agent rules and `docs/AI_WORKFLOW.md` for workflow safeguards.

## Verification checklist
Run from the repository root when Rust and native prerequisites are available:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

Discover the actual .NET solution path and SDK before running restore/build/test. For audio-engine changes, automated checks are not sufficient: test playback, track lifecycle, transport controls, device switching and clean exit on supported hardware, recording OS, device and sample rate.

Update this snapshot when its facts change. Mark something verified only with successful command or CI evidence; record failures and skipped checks plainly.

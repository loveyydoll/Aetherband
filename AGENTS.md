# Aetherband — Agent Instructions & Engineering Status

> **Purpose:** This file is the working contract for AI coding agents and human contributors. It records the project's verified direction, engineering constraints, current patch status, and unfinished work. Update it whenever implementation or verification status changes.
>
> **Status snapshot:** 2026-10-16. Treat status below as a snapshot, not proof that code compiles. Always inspect the current branch and CI before continuing.

## 1. Project identity and goal

- **Project:** Aetherband, an early-stage desktop audio workstation and the future audio application in the broader Aether creative suite.
- **Repository:** https://github.com/loveyydoll/Aetherband
- **Primary stack:** Rust audio engine, C ABI in `bindings/c_abi/`, C#/.NET desktop application using Avalonia.
- **Target platforms:** Windows and macOS, subject to the actual status of platform-specific audio/backend support.
- **Current stage:** Early alpha / work in progress. Do not present it as production-ready or feature-complete.
- **Current engineering priority:** establish audio correctness, ownership/lifecycle safety, repeatable CI and trustworthy documentation before expanding feature scope.

## 2. Instructions for AI agents

### Before changing anything

1. Read this file and `docs/AI_WORKFLOW.md`. Inspect the relevant source files and current git/branch/PR state before editing.
2. Confirm the repository's current structure and APIs; documentation and old paths may be stale.
3. Identify the exact behavior being changed and the failure mode it addresses.
4. Make the smallest coherent change that can be reviewed and tested. Avoid unrelated refactors.
5. Do not edit `main` directly for risky engineering work. Use a focused branch and a pull request.
6. Do not assume a prior agent's patch is correct simply because it is committed or described here. Review the code and CI evidence yourself.

### Required reporting discipline

For every meaningful task, report these separately:

- **Implemented:** changes actually present in the diff.
- **Not implemented:** planned items that remain untouched.
- **Not verified:** checks that were not run or whose result is pending.
- **Verified:** checks with recorded, successful command/CI output.
- **Known risks:** limitations or potential regressions still open.

Never claim code compiled, tests passed, a feature works at runtime, or real-time safety is proven unless the corresponding verification was actually performed. A CI workflow existing is not the same as CI passing.

### Non-negotiable engineering rules

1. **Real-time audio callback:** no filesystem/network I/O, blocking locks, sleeps, unbounded loops, logging, or routine heap allocation/deallocation/destructor work on the callback thread. Keep callback work bounded. Use explicit ownership-transfer/deferred-reclamation designs for resources that need destruction.
2. **Concurrency:** document producer/consumer ownership and thread responsibilities. Do not silently replace bounded SPSC communication with locks or unbounded queues. Consider shutdown, queue-full behavior, backpressure, and ownership on every error path.
3. **No panic paths in audio processing:** avoid `unwrap()`, `expect()`, unchecked assumptions and panic-capable operations in code reachable from the real-time callback. Unit-test invalid inputs.
4. **Device configuration:** initialize sample-rate-dependent DSP using the actual selected output configuration. Handle channel counts and buffer sizes explicitly.
5. **Decoder lifecycle:** every worker needs a clear stop, join, error-reporting, and resource-reclamation strategy. Do not block the audio callback while waiting for a worker.
6. **Dependencies:** do not add a crate or NuGet package without explaining its purpose, license, maintenance status, and why existing code or standard-library functionality is insufficient.
7. **C ABI:** changes to exported functions/types in `bindings/c_abi/` must include compatibility review and regeneration/verification of the C# bindings (including csbindgen where applicable).
8. **Errors:** surface actionable errors to the owning layer/UI. Do not log-and-ignore failures when the application needs to respond.
9. **Data safety:** never run destructive Git commands or overwrite user work without explicit authorization.
10. **Architecture:** record significant architectural decisions and trade-offs. Do not introduce a new framework, subsystem, or dependency silently.

## 3. Architecture and coding conventions

- Keep the audio engine independent of UI concerns.
- Keep platform audio-device interaction in the device/backend layer.
- Keep file decoding and resampling off the real-time callback.
- Use bounded queues for cross-thread commands/telemetry; specify queue-full behavior.
- Keep Rust formatting consistent with `cargo fmt`; prefer explicit domain errors and readable ownership flow.
- Keep UI I/O and long-running operations asynchronous; do not block UI event handlers.
- Follow existing repository patterns only after checking that they are current and internally consistent. Some existing docs still mention the previous project names and paths; do not copy those blindly.

## 4. Current implementation status

### Changes made on `fix/audio-engine-correctness`

These changes have been committed to the branch and included in draft PR #1:

- [x] Bounded audio command handling to at most 128 commands per callback.
- [x] Added a reverse SPSC queue and fixed-capacity deferred storage so removed/rejected track players can be reclaimed by the control thread instead of routinely being destroyed in the callback.
- [x] Kept track-player heap allocations boxed while stored in the audio track slots.
- [x] Guarded the zero-channel output case and explicitly cleared output channels beyond stereo.
- [x] Initialized the processor using the selected output device's reported default sample rate rather than hard-coded 48 kHz.
- [x] Added decoder worker join handles and stop/join behavior on decoder shutdown.
- [x] Added regression tests for zero-channel and extra-channel output handling.
- [x] Added `.github/workflows/rust.yml` to run formatting, workspace compilation and tests.

**Review these changes critically.** They are implementation attempts, not yet verified fixes. In particular, the real-time ownership design needs tests and review for all queue-full/error paths; the callback must not log or free resources as a fallback.

### Verification state

- **Local Rust checks:** not run by the agent that authored the branch.
- **Rust GitHub Actions:** workflow was started for the PR; the last observed status was in progress. Re-check the live run before reporting its result.
- **Existing .NET workflow:** recent runs on `main` were failing at the time of this snapshot. Inspect their logs before changing the .NET workflow; do not assume the failure is caused by the Rust patch.
- **Runtime audio checks:** not performed.
- **Merge status:** PR #1 is a draft and must not be merged until review and required checks pass.

Links:
- Draft PR: https://github.com/loveyydoll/Aetherband/pull/1
- Rust workflow: https://github.com/loveyydoll/Aetherband/actions/workflows/rust.yml

## 5. Known issues not yet resolved

### P0 — Transport and decoder coordination

- Stop resets audio-side playback state but does not yet have a proven protocol for resetting/restarting each decoder's source position.
- Seek must coordinate the audio playhead with decoder seeking, buffered audio invalidation, and resumption. Changing only a playhead value is insufficient.
- Add tests for Stop → Play, Seek while playing, Seek while stopped, repeated seeks, end-of-file, and decoder backpressure.

### P0 — Device switching and active tracks

- Recreating the audio processor can discard the processor's active track slots while control-side track metadata/decoder handles remain.
- Device switching must either preserve/rebuild active track players safely or fail without corrupting the existing session.
- Test switching devices with zero, one, and multiple tracks, including a device-open failure.

### P1 — Real-time safety proof

- Review all audio callback paths, including AddTrack rejection, RemoveTrack, command floods, queue-full behavior, processor drop, and engine shutdown.
- Ensure no destructor/deallocation, logging, blocking wait, I/O, lock, or unbounded loop can occur in the callback.
- Add meaningful allocation/real-time-safety tests covering actual track lifecycle commands, not only a test tone.
- The current fixed scratch-buffer cap of 2048 frames needs an explicit, tested policy for larger callback buffers.

### P1 — Decoder errors and shutdown

- Decoder worker failures are logged but are not yet delivered to the UI/engine as structured errors.
- Verify stop/join cannot hang indefinitely and that every worker terminates on track removal and engine shutdown.
- Test corrupted/unsupported media, early EOF, full decoder ring buffer, and rapid load/remove sequences.

### P1 — Sample rate, output and device tests

- Validate the new sample-rate initialization for both default and explicitly selected devices.
- Test mono, stereo, multichannel, zero-channel defensive behavior, and buffer sizes above the configured maximum.
- Ensure device reconfiguration doesn't leave the UI and processor with contradictory state.

### P2 — Repository coherence

- Update stale `CustomDAW` / `RouletteStudio` naming, repository metadata, and outdated paths in docs after correctness work is stable.
- Reconcile `docs/AI_WORKFLOW.md`, `docs/VISION.md`, `docs/ROADMAP.md`, README, solution paths, and actual code. Avoid duplicating conflicting status information: this file is the current agent handoff; detailed design docs should explain intended architecture, not pretend incomplete features already exist.

## 6. Verification checklist

Run from the repository root in an environment with Rust and required native audio development libraries installed:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

Then, where supported, verify the desktop solution:

```sh
dotnet restore
dotnet build
dotnet test
```

The exact .NET solution path and SDK version must be checked against the current repository before running these commands.

For audio-engine changes, automated checks are necessary but not sufficient. Also test the actual desktop app with a real output device, confirm playback/meters, exercise track lifecycle and transport controls, switch devices, and exit cleanly. Record OS, device, sample rate, and observed results.

## 7. Update this file after every task

When completing a task, update the status above in the same branch/PR:

1. Move an item to **implemented** only when code is present.
2. Move it to **verified** only when the check has actually passed; include the command or CI run link.
3. Leave unfinished work explicitly listed under **Known issues not yet resolved**.
4. Record failed checks and the useful failure summary—do not hide or weaken a failing test to get a green build.
5. Remove outdated claims when code changes; keep dates and PR/branch references current.
6. Keep this file concise enough for agents to read first, and link to detailed design documents rather than copying entire specifications here.

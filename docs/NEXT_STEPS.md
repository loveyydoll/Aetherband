# Aetherband — Documentation Audit and Next Steps

**Reviewed:** 2026-10-16  
**Scope:** Markdown documentation on `main`, plus the currently discoverable Stop issue and stabilization pull request.  
**Purpose:** Contributor handoff. This is a documentation-based review, not a source-code audit or a claim that builds/tests passed.

## Executive summary

Aetherband is an early-alpha desktop DAW with a Rust real-time audio engine, a flat C ABI, and a C#/.NET 10 Avalonia UI. The docs consistently identify transport/lifecycle correctness and verification as the immediate priority. Do not start major feature work until the stabilization gate is demonstrated.

The README says the Stop behavior has been fixed in the core, but also says runtime confirmation is still needed. GitHub issue [#5](https://github.com/loveyydoll/Aetherband/issues/5) describes the user-visible failure (the playhead resets while audio reportedly continues) and explicitly requires automated regression coverage **and** manual runtime confirmation. Treat Stop as not yet accepted until both are evidenced.

## Priority order

### P0 — Finish transport stabilization

Track this work against [issue #5](https://github.com/loveyydoll/Aetherband/issues/5) and [PR #7: Fix/phase 1 3 stabilization](https://github.com/loveyydoll/Aetherband/pull/7).

- [ ] Reproduce Stop with the diagnostic tone disabled, first with one imported track and then multiple tracks.
- [ ] Trace command acceptance end-to-end: C# UI → P/Invoke/C ABI result → bounded command queue → audio callback consumption → authoritative telemetry.
- [ ] Ensure the UI reports queue rejection/errors instead of optimistically claiming a command succeeded or resetting the playhead as if Stop were confirmed.
- [ ] Add/confirm a regression test: Play produces non-silent output; Stop produces silence and stopped telemetry/playhead frame zero; Play after Stop restarts at the beginning.
- [ ] Test Stop while playing, paused, at EOF, immediately after Play, with multiple tracks, and repeated Stop.
- [ ] Verify decoder restart/rewind semantics. Emptying buffered audio alone does not rewind a decoder worker.
- [ ] Confirm Pause is distinct from Stop and Seek coordinates playhead, decoder position, stale buffered samples, and resumption.
- [ ] Preserve callback guarantees: bounded work, no blocking locks/I/O/logging, and no allocation/deallocation or arbitrary resource destruction on the audio thread.

**Acceptance:** Automated regression tests pass, manual playback confirms silence after Stop and correct restart, and the result is reflected in telemetry rather than only local UI state.

### P1 — Verify lifecycle and real-time safety

- [ ] Test device switching with zero, one, and multiple tracks, including failure to open the replacement device.
- [ ] Test unplugged/lost devices, stream errors, shutdown, track removal, corrupt/unsupported media, early EOF, decoder queue saturation, and rapid load/remove.
- [ ] Audit queue-full/rejected commands and resource ownership/reclamation paths.
- [ ] Test mono, stereo, multichannel, zero-channel defensive handling, and oversized callback buffers.
- [ ] Verify sample-rate initialization and reconfiguration against the selected device.
- [ ] Confirm worker cancellation/join cannot hang and errors reach the UI in a structured way.

### P1 — Run and record verification

Run from the repository root where the required toolchains and native dependencies are available:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

Then discover the current .NET solution/project and SDK from the repository, and run the appropriate restore, build, and test commands. Do not assume a historical solution path is current.

- [ ] Inspect the latest GitHub Actions runs and latest commit for each required check; record failures and skipped stages.
- [ ] Run the repository verification script if applicable.
- [ ] Perform manual runtime checks on available supported hardware; record OS, device, sample rate, and outcomes.
- [ ] Do not claim macOS verification unless it was actually performed on macOS.
- [ ] Update PR #7's verification checklist with exact commands/results before review or merge.

**Evidence status for this audit:** I reviewed Markdown files and GitHub issue/PR metadata. I did not run the repository build, tests, or hardware playback, and this document does not claim they passed.

### P2 — Align documentation and contracts

- [ ] Reconcile the README's “Stop fixed in core” wording with the still-open runtime acceptance gate. Prefer “core fix implemented; runtime acceptance pending” until the manual test is complete.
- [ ] Align the supported-format lists. The README describes WAV, FLAC, MP3, OGG, and AAC/M4A; `docs/REQUIREMENTS.md` currently names WAV, AIFF, FLAC, and MP3 in its decoding requirement.
- [ ] Reconcile the C ABI contract: `docs/API_CONTRACT.md` mentions `daw_engine_stop`, but its exported-function list documents `daw_engine_send_command` for transport commands. Confirm the real symbols and document the actual API.
- [ ] Review status claims in `docs/ENGINEERING_STATUS.md`: it references older draft PRs/branch context. Refresh it against current source, issue/PR state, and CI before treating it as current.
- [ ] Fix literal escaped newline sequences (`\\n`) that appear in several Markdown sections (notably the transport notes in `docs/AI_WORKFLOW.md`, `docs/AUDIO_ENGINE.md`, `docs/API_CONTRACT.md`, and the implementation note in `docs/DECISIONS.md`) so headings and paragraphs render normally.
- [ ] Keep project/folder naming notes (for example, legacy `RouletteStudio` paths) consistent with the current solution and source tree.
- [ ] Ensure the README, roadmap, requirements, engineering snapshot, and PR checklist agree on which milestones are implemented, planned, and runtime-verified.

### P3 — Resume feature work only after the gate is green

After stabilization, prioritize the planned Phase 4 capabilities:
1. Versioned project save/load and asset packaging.
2. Waveform peak generation/caching.
3. Audio input recording and background file writing.
4. Offline WAV export and recovery/autosave.

MIDI/instruments and effects/plugin hosting remain later milestones. Keep UI redesign work presentation-focused and do not let it weaken audio-thread guarantees or delay stabilization.

## Markdown files reviewed

| File | Review notes |
|---|---|
| [README.md](../README.md) | Primary user-facing status, build/test commands, stack and phase overview. Stop wording should distinguish core implementation from runtime acceptance. |
| [docs/VISION.md](VISION.md) | Product direction and MVP boundaries; long-term goals must not be mistaken for current features. |
| [docs/REQUIREMENTS.md](REQUIREMENTS.md) | Functional/non-functional acceptance criteria; audio-format list differs from README. |
| [docs/ARCHITECTURE.md](ARCHITECTURE.md) | Layer boundaries, responsibilities and data flows; verify design claims against source when doing code work. |
| [docs/AUDIO_ENGINE.md](AUDIO_ENGINE.md) | Real-time callback constraints and transport/lifecycle notes; transport note has literal escaped newline formatting. |
| [docs/API_CONTRACT.md](API_CONTRACT.md) | C ABI, error codes, commands and telemetry; reconcile `daw_engine_stop` wording with listed exports. |
| [docs/ROADMAP.md](ROADMAP.md) | Current stabilization gate and phase ordering; use as the feature sequencing reference. |
| [docs/DECISIONS.md](DECISIONS.md) | Architecture decisions; implementation note has literal escaped newline formatting and plugin phase wording should stay aligned with roadmap. |
| [docs/AI_WORKFLOW.md](AI_WORKFLOW.md) | Verification and AI contributor safeguards; project caution section has literal escaped newline formatting. |
| [docs/ENGINEERING_STATUS.md](ENGINEERING_STATUS.md) | Dated engineering snapshot, but branch/PR references appear older than current stabilization work. Refresh before relying on it. |
| [docs/GITHUB_RULESETS.md](GITHUB_RULESETS.md) | Clearly labels branch protection as proposed rather than applied; re-check actual settings separately. |
| [AGENTS.md](../AGENTS.md) | Contributor/agent entry point and required completion report. |
| [.github/instructions/audio-realtime.instructions.md](../.github/instructions/audio-realtime.instructions.md) | Callback, queue, ownership, lifecycle and evidence requirements. |

## Current GitHub references

- [Issue #5 — Fix Stop transport: audio continues after playhead resets](https://github.com/loveyydoll/Aetherband/issues/5)
- [PR #7 — Fix/phase 1 3 stabilization](https://github.com/loveyydoll/Aetherband/pull/7)

Re-check their live state and latest CI before acting; this audit records what was discoverable during review and is not a substitute for current CI evidence.

## Definition of done for this stabilization pass

- [ ] Stop regression is covered by an automated test and passes.
- [ ] Manual Play/Pause/Stop/Seek and restart behavior is verified on real hardware.
- [ ] Decoder, track, device and shutdown edge cases are tested or explicitly tracked.
- [ ] Rust and .NET checks have actual passing results; skipped checks are disclosed.
- [ ] Documentation claims match verified behavior and the current API.
- [ ] PR review checklist is complete, and a human reviewer approves the changes before merge.

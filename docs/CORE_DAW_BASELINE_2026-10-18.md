# Core DAW baseline — 2026-10-18

## Scope

This is the first **small test-first PR** in the Core DAW stabilization sequence. It adds callback regression cases for previously under-tested output shapes. It intentionally does not claim to have fixed the existing Clippy findings, implemented native mixer UI, or completed project persistence.

## New regression coverage

- Six-channel active output: L/R carry the rendered test tone; channels 3–6 are explicitly cleared, even if their destination samples held stale data.
- Oversized stereo output: frames beyond the preallocated `MAX_BLOCK_FRAMES` scratch capacity are silent, even when the callback is playing a test tone.

The tests exercise `AudioProcessor::process_interleaved` without a physical device. They do **not** prove hardware playback, device recovery, or absence of dropouts.

## Required checks before merging

From the repository root:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```

From `apps/desktop/`:

```sh
flutter pub get
flutter analyze
flutter test
```

**Verification status at authoring:** New tests have not been executed in a checked-out build environment. The 2026-10-18 verification snapshot reports 37 pre-existing Rust tests and 12 Flutter tests passing locally on Windows, but strict Clippy failing on existing findings. Do not mark this PR as passing before actual CI results are recorded.

## Follow-up stabilization tasks

1. Run the above checks on current main and this branch, and record failing diagnostics verbatim.
2. Repair Clippy findings in small, behavior-preserving commits, avoiding lint suppression; prefer a dedicated follow-up PR when broad DSP changes would obscure these tests.
3. Preserve the real-time callback contract (no allocation, blocking locks or file I/O) and existing Stop/Pause behavior.
4. Record an independent Windows hardware playback/device-switching check and a macOS native lifecycle check.
5. Measure callback P50/P95/P99 processing time against the configured device buffer deadline using a reproducible benchmark, not invented performance numbers.
6. Start the real session-model PR after baseline checks have credible evidence.

## Next Core DAW PR sequence

1. Session state with stable track, clip, and source IDs, explicitly separate from temporary native IDs.
2. Versioned save/reopen with missing-media recovery and atomic writes.
3. Native clip scheduling and real waveform peaks, with audible timing tests.
4. Track/master mixer binding to real Rust state, including solo semantics.
5. Deterministic offline stereo WAV export.

See `docs/FEATURE_TRACKER.md` and `docs/PROJECT_STATE.md` for the latest known feature boundaries.

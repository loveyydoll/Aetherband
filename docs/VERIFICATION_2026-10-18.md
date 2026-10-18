# Audio import and lifecycle verification — 2026-10-18

Scope: `fix/real-audio-import`, based on main `2c4c475`. This is an automated Windows verification record, not a production-readiness claim.

## Implemented

- Repaired Rust formatting in graph/core source that prevented CI from reaching compilation/tests.
- Checked in Flutter's analyzer configuration so local checks use the same Flutter lint rules as CI-generated runners, and fixed the brace warnings exposed by CI. Only generated build output is excluded; application and test code remain analyzed.
- Added ABI 0.3.0 source-frame/rate/channel metadata and matching Dart declarations; source duration determines imported clip width in the ruler/playhead coordinate system. Zero/missing duration is labelled unknown.
- Added a visible import action, loading guard, cancellation/error handling and loaded-track count. Import rewinds transport. Imported audio does not show invented waveforms or permit visual-only dragging/mixing.
- Moved synchronous FFI operations to a long-lived Dart isolate. The opaque C handle keeps the actual non-Send engine/CPAL stream on a dedicated Rust thread. Calls, polling and shutdown are serialized; both control backlogs are bounded at 64. No new package/crate was added.
- Fixed removal queue rejection to retain metadata/decoder state. UI removal captures its target before awaiting. Retry disposes the previous engine and clears stale native IDs. Large track lists scroll vertically; menus scroll at constrained widths.
- Refreshed the existing dependency lockfiles. The Rust lockfile only removes the obsolete, already-unused csbindgen entry.

## Verified locally

| Check | Result |
|---|---|
| `cargo fmt --all -- --check` | Passed |
| `cargo check --workspace --all-targets --offline` | Passed |
| `cargo test --workspace --all-targets --offline` | Passed: 37 tests (30 core, 1 callback allocation, 6 FFI/control-thread tests) |
| `cargo build -p daw_core_ffi --offline` | Passed; Windows debug DLL built |
| `flutter pub get` | Passed using existing manifest dependencies |
| `flutter analyze` | Passed: no issues |
| `flutter test --reporter expanded` with `AETHERBAND_NATIVE_LIBRARY` pointing at the built DLL | Passed: 12 tests, including native Windows integration; no skips |
| `flutter build windows --debug` | Passed in a temporary runner project using identical `lib/` source |
| `git diff --check` | Passed |

The temporary Windows build needed an unprivileged directory junction for the existing file-picker plugin because Developer Mode/symbolic links were unavailable. No OS settings or repository CI requirements were changed. Generated runners/build output are excluded from this change.

The native integration test uses a generated quiet 44.1 kHz mono WAV with a Unicode filename. It checks source metadata, native playing/nonzero-peak telemetry, Pause silence, Stop/zero-playhead/silence, replay after Stop, track removal and invalid-file failures, backlog rejection, disposal queued behind import, and rejection after disposal. Unit/widget tests cover non-Send thread ownership through destruction, queue saturation/retry, ABI layout, cancellation, unknown duration, compact layout, selection changes during removal, failed removal retry, workspace disposal during import, and engine replacement.

## Not verified / known risks

- `cargo clippy --workspace --all-targets --offline -- -D warnings` fails on existing findings in unchanged core audio/decoder/DSP/track code: constant-size chunks, collapsible if, range containment and missing Default. No lint suppression or test weakening was introduced.
- macOS builds/runtime, manual file-dialog interaction, device switching/loss, independent listening/loopback capture, long/large sessions and non-WAV imports were not verified locally. Test telemetry does not prove physical speaker output.
- Forced worker/isolate termination and Flutter hot restart can bypass orderly disposal; this needs dedicated lifecycle testing.
- Imported tracks currently start at zero; import rewinds transport. Reconnect creates an empty native inventory and requires reimport. Session persistence, actual waveforms, native clip edits, imported mixer controls, recording and export remain unfinished.
- The synchronous C ABI must be called off the caller's UI thread. The additional native control hop needs performance profiling. The real-time callback itself was not changed.
- Remote CI results must be inspected on the pull request; local success is not remote CI evidence.

## Next step

Verify macOS import/transport/shutdown and physical output, then implement real waveform peaks and the smallest persistent session round trip.

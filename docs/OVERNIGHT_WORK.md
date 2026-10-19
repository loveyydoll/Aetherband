# Audio and HypnoSynth implementation

Requested outcome: one Windows-only PR restoring audio in the existing Flutter workspace, adding an original HypnoSynth and implementing the core DAW workflows already implied by the interface. Preserve the existing UI, keep `sources/` read-only, and do not alter the conflicting Desktop checkout.

Working branch: `feat/hypnosynth-daw-foundations`. Pull request: [#33](https://github.com/loveyydoll/Aetherband/pull/33), open and unmerged. Latest validated head: `bec19b7f88554fb25f8dccbc84b42a98b1e13540`.

## Implemented

- Repaired Windows output conversion for device-native CPAL formats, full callback buffers, stream error reporting and safe stream/resource teardown. Output-device switching restores instrument, transport and mixer performance state.
- Added original polyphonic HypnoSynth with three authored presets, live keyboard input, performance controls, an editable 16-step note/rest sequence, tempo/metronome, panic and session persistence. Musical references guided original sound design; no artist recordings or copied patches were used.
- Replaced visual demo tracks with a real empty session and connected audio import/playback, track mixer controls, clip positioning, save/reopen, Windows input recording, and stereo WAV export.
- Reused only Soundcraft's ADSR envelope code with upstream MIT attribution and licence in `third_party/soundcraft/`. Rust remains the real-time engine and Dart/Flutter remains the UI; no other language showed a concrete advantage for this scope.

## Verification

- Windows Rust: formatting, workspace Clippy, 47 core tests, 8 C ABI tests, callback allocation test, output-device smoke target and release C ABI build pass. Clippy emits existing C ABI missing-safety-documentation warnings.
- Windows Flutter: analysis clean, 33 tests pass, native FFI integration test passes against the release DLL and default output device, and the Windows desktop debug build succeeds.
- Remote Rust and Windows Flutter CI pass on head `bec19b7`, including the Windows desktop build.
- Targeted sequence tests cover callback note/rest output, offline export, session round trips and older-session defaults, UI edits through the native event path, and sequence restoration after an output-device change.

## Remaining gaps and limits

Physical listening through speakers/loopback and real microphone/line-in recording remain unverified. Full MIDI regions/file interchange, waveform rendering, clip split/trim/resize, undo/redo, automation, effects processing and plugin hosting remain incomplete. These are recorded in `docs/FEATURE_TRACKER.md`; the PR does not claim complete commercial DAW parity.


## DAW transport shortcut follow-up (2026-10-19)

- Space now toggles the real native transport play/pause operation. Added a widget regression test; Flutter analysis is clean and all 33 widget tests pass. This small DAW workflow improvement is being added to PR #33.

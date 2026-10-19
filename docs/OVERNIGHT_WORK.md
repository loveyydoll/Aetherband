# Aetherband Windows audio and DAW foundations

Implement the user's Windows-only audio repair, original HypnoSynth, and core DAW workflows in one PR. Preserve the existing UI and conflicting Desktop checkout; `sources/` is read-only. Soundcraft reuse is limited to its MIT-licensed ADSR envelope, with attribution and licence in `third_party/soundcraft/`. Rust remains the real-time engine and Flutter/Dart the desktop UI.

Branch: `feat/hypnosynth-daw-foundations`. PR: [#33](https://github.com/loveyydoll/Aetherband/pull/33), open and unmerged. The local branch integrates fetched PR head `6fe45319de278508bf46dcd5398f5698cecaabfb`; after each update, publish only by fast-forwarding this branch and refresh remote CI. Keep all work in this one PR.

## Implemented in the current working tree

- Windows output uses native CPAL formats, processes complete callback buffers, reports stream errors, and releases stream resources safely. Output-device changes restore synth, transport and mixer configuration, rescale clip positions for the new sample rate, and restart stopped at the beginning.
- HypnoSynth is an original polyphonic instrument with three authored presets, live keyboard, performance controls, panic, tempo/metronome, and an editable, persisted 16-step note/rest pattern that plays through the callback and offline render. The musical references informed original sound design; no recordings or patches were copied.
- Sessions start empty and connect imported audio, timeline movement with default beat snapping and a free-placement toggle, mixer controls, session save/reopen, Windows input recording, stereo WAV export, Space/R transport shortcuts and bar/timeline seeking to the Rust engine through ABI 0.10.0 and the Dart worker isolate. The Region menu splits and joins source-contiguous regions and trims a selected region to the stopped playhead; source-bounded changes are mixed, moved, saved and restored from session schema v5. Schema v1-v4 remain readable.
- PCM and IEEE-float WAV files render measured peak waveforms loaded off the UI isolate; unsupported formats show an explicit unavailable state.
- Undo/redo restores timeline clip moves, region splits/joins and trims through the native engine and session model, with Ctrl+Z/Ctrl+Y and generic Edit-menu actions. Split regions participate in copy/paste and duplication.
- Track > Add Instrument Track now creates a single named HypnoSynth arrangement track, which can be selected, renamed, deleted and saved/reopened. Its mixer gain, pan, mute and solo reach the real-time engine and offline mixdown. Session schema v5 stores track identity and mixer state and continues to read v1-v4. The 16-step phrase remains session-wide; pattern clips and independent per-track MIDI routing are still not implemented.
- Only the Soundcraft ADSR code was reused. No other language showed a concrete subsystem advantage for this change.

## Local verification on 2026-10-19

- Windows `cargo test --workspace --jobs 1`: 51 core tests, 10 C ABI tests, callback-allocation test and WASAPI smoke target pass. Generated WAV tests verify source seek and bounded region decode; the C ABI crate disables irrelevant doctests to avoid duplicate `daw_core` crate candidates.
- Windows workspace Clippy passes with existing C ABI missing-`# Safety` documentation warnings; optimized C ABI DLL build passes.
- Direct Dart analysis reports no errors. The local Flutter launcher could not run because the SDK lockfile at `C:\src\flutter\bin\cache\lockfile` is inaccessible; current-head Windows CI run 110 passed analysis, all 57 Flutter tests (one optional device test skipped), and the desktop build at `aa13944`. Split/join/trim undo-redo, split copy/duplicate and schema-v4 round-trip tests passed.
- A separate opt-in WASAPI smoke test reaches nonzero HypnoSynth samples and shuts down cleanly. This confirms callback output, not speaker audibility.
- The Windows runner is checked into the desktop project. The advertised Ctrl+Alt+E export shortcut, selected-track Delete action, F2 rename shortcut and Ctrl+arrow bar seeking are tested. Current-head Rust run 303 and Flutter desktop run 100 pass on `56ddb75`; the Flutter run includes the Windows desktop build. Earlier local Rust run 297 and Flutter desktop run 93 pass on `8c4a667`.

## Remaining limits and next work

Physical speaker/headphone listening and real microphone/line-in capture remain unverified. The recorder writes to a background stereo PCM16 WAV writer and imports the finalized take, but hardware capture and sustained queue-drop behavior need a real input device. Waveform display currently supports PCM and IEEE-float WAV; compressed WAV and other containers have an honest unavailable state. Full MIDI regions and file interchange, automation, effects, bounce-in-place and plugin hosting remain future work.

Before the overnight window ends, review the full diff, publish any final changes to PR #33 without merging, refresh the PR body with current evidence and verify CI on its latest head. Report physical audio and recording limits accurately.

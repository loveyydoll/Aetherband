# Aetherband Windows audio and DAW foundations

Implement the user's Windows-only audio repair, original HypnoSynth, and core DAW workflows in one PR. Preserve the existing UI and conflicting Desktop checkout; `sources/` is read-only. Soundcraft reuse is limited to its MIT-licensed ADSR envelope, with attribution and licence in `third_party/soundcraft/`. Rust remains the real-time engine and Flutter/Dart the desktop UI.

Branch: `feat/hypnosynth-daw-foundations`. PR: [#33](https://github.com/loveyydoll/Aetherband/pull/33), open and unmerged. The local branch integrates fetched PR head `6fe45319de278508bf46dcd5398f5698cecaabfb`; after each update, publish only by fast-forwarding this branch and refresh remote CI. Keep all work in this one PR.

## Implemented in the current working tree

- Windows output uses native CPAL formats, processes complete callback buffers, reports stream errors, and releases stream resources safely. Output-device changes restore synth, transport and mixer configuration, rescale clip positions for the new sample rate, and restart stopped at the beginning.
- HypnoSynth is an original polyphonic instrument with three authored presets, live keyboard, performance controls, panic, tempo/metronome, and an editable, persisted 16-step note/rest pattern that plays through the callback and offline render. The musical references informed original sound design; no recordings or patches were copied.
- Sessions start empty and connect imported audio, timeline movement with default beat snapping and a free-placement toggle, mixer controls, session save/reopen, Windows input recording, stereo WAV export and Space/R transport shortcuts to the Rust engine through ABI 0.8.0 and the Dart worker isolate.
- PCM and IEEE-float WAV files render measured peak waveforms loaded off the UI isolate; unsupported formats show an explicit unavailable state.
- Undo/redo restores timeline clip moves through the native engine and session model, with Ctrl+Z/Ctrl+Y and Edit-menu actions. History is limited to clip movement so far.
- Only the Soundcraft ADSR code was reused. No other language showed a concrete subsystem advantage for this change.

## Local verification on 2026-10-19

- Windows `cargo test --workspace --jobs 1`: 47 core tests, 8 C ABI tests, callback-allocation test and WASAPI smoke target pass. The C ABI crate disables irrelevant doctests to avoid duplicate `daw_core` crate candidates.
- Windows workspace Clippy passes with existing C ABI missing-`# Safety` documentation warnings; optimized C ABI DLL build passes.
- Flutter analysis is clean; 43 Flutter tests pass and the optional native test is skipped in the default suite. The focused Windows FFI integration test passes against the freshly built release DLL and default output device, covering device selection, synth/sequence state restoration, transport, import, mixer, stereo export and shutdown.
- A separate opt-in WASAPI smoke test reaches nonzero HypnoSynth samples and shuts down cleanly. This confirms callback output, not speaker audibility.
- The Windows runner is now checked into the desktop project; its local debug build passes. Published commit `7ed5b8c` passes both Windows CI workflows (Rust run 283 and Flutter desktop run 79). Local duplicate-track work passes all 43 Flutter tests, analysis and the Windows debug build; it still needs publishing and remote CI.

## Remaining limits and next work

Physical speaker/headphone listening and real microphone/line-in capture remain unverified. The recorder writes to a background stereo PCM16 WAV writer and imports the finalized take, but hardware capture and sustained queue-drop behavior need a real input device. Waveform display currently supports PCM and IEEE-float WAV; compressed WAV and other containers have an honest unavailable state. Full MIDI regions and file interchange, clip split/trim/resize, general editing history, automation, effects and plugin hosting remain future work.

Before the overnight window ends, review the full diff, finish formatting/analyze/tests and Windows desktop build, publish these changes to PR #33 without merging, refresh one PR body with current evidence and wait for its latest Windows CI runs. Report physical audio and recording limits accurately.

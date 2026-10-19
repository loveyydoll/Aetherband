# PR #33 Verification Checklist

**Scope:** Windows audio path restoration, HypnoSynth, session schema v6, timeline editing foundations, and PCM24 mixdown/recording.

**Purpose:** Keep a clear, honest record of what has been proven automatically versus what still requires real hardware and human listening. This document is intentionally narrow — it only covers the work introduced or substantially changed in PR #33.

---

## Status vocabulary (use these terms only)

| Term | Meaning |
|------|---------|
| **CI green** | The relevant GitHub Actions workflow passed on the PR head. |
| **Unit / integration tested** | Automated tests exist and passed (Rust or Dart). Does **not** imply real audio hardware was involved. |
| **Hardware observed** | A human ran the built application on a real Windows machine, selected a real output (or input) device, and recorded the result. |
| **Unverified** | Code exists, but the behaviour has not been confirmed on real hardware or the relevant automated test is missing. |

Do not promote a feature to “working” on the basis of CI or unit tests alone when the feature involves real-time audio I/O.

---

## What PR #33 claims to deliver

- End-to-end Windows audio output path (CPAL / WASAPI).
- Original HypnoSynth instrument (presets, live notes, 16-step sequencer, arrangement patterns).
- Session schema v6 with save / reopen of imported tracks + mixer state + HypnoSynth state.
- Timeline editing primitives (source-bounded trim / split / join, undo/redo).
- Mixdown to signed stereo PCM24.
- Windows input recording path that writes PCM24 and adds the result as a track.

---

## Automated evidence (expected on the PR)

These should be green before merge:

- [ ] Rust: `cargo fmt --all -- --check`
- [ ] Rust: `cargo check --workspace --all-targets`
- [ ] Rust: `cargo test --workspace --all-targets`
- [ ] Rust: Clippy (or explicit acceptance of remaining findings)
- [ ] Rust: optimized `daw_core_ffi` DLL build succeeds
- [ ] Flutter / Dart: `flutter analyze` clean
- [ ] Flutter / Dart: widget + session tests pass
- [ ] Windows CI workflows (Rust + Flutter desktop) pass on the final PR head

Record the exact CI run URLs on the PR when they pass.

---

## Hardware verification checklist (Windows)

Run these on a real Windows machine with working speakers/headphones. Prefer a Release build of the native library + Flutter app.

### 1. Basic playback & transport

- [ ] Launch the app; default output device is selected without error.
- [ ] Import a short WAV file → it appears as a real track (not a demo clip).
- [ ] Play → audible output.
- [ ] Pause → silence, playhead stays.
- [ ] Stop → silence **and** playhead returns to zero.
- [ ] Play again after Stop → restarts from the beginning.
- [ ] Clean shutdown (no hang, no crash, no stuck audio stream).

### 2. Mixer

- [ ] Gain / pan / mute on an imported track produce the expected audible change.
- [ ] Mute keeps the track advancing so that unmute resumes at the correct position.
- [ ] Solo (if exposed) behaves as documented; if not implemented, the UI must not pretend it works.

### 3. HypnoSynth

- [ ] HypnoSynth track is present on a new session.
- [ ] Live note input produces sound.
- [ ] Switching between the three original presets changes the timbre.
- [ ] 16-step sequencer / phrase playback is audible and tempo-aware.
- [ ] Panic / all-notes-off stops hanging notes.
- [ ] Pattern regions placed on the arrangement play at the correct time.
- [ ] Gain / pan / mute on the HypnoSynth track work.

### 4. Session persistence

- [ ] Save a session that contains imported audio + HypnoSynth settings + pattern data.
- [ ] Close the app, reopen the session → tracks, mixer values, and synth state restore.
- [ ] Missing source file is reported without destroying the rest of the session.

### 5. Mixdown & recording

- [ ] Mixdown produces a valid signed stereo PCM24 WAV at the expected sample rate.
- [ ] The exported file is audible and roughly matches the session length.
- [ ] (Optional but valuable) Input recording captures from a real microphone/line-in and the resulting file is added as a playable track.

### 6. Device switching (if exposed)

- [ ] Switch output device while tracks are loaded → audio continues or fails with a clear error (no silent broken state).
- [ ] Track gain/pan/mute and HypnoSynth state survive the switch.

---

## Known limitations that must stay visible

These are **not** bugs in PR #33; they are explicit out-of-scope items. Keep them listed in the PR description and README so reviewers do not treat them as regressions:

- Physical speaker/headphone listening and real microphone capture are still **unverified** until the hardware checklist above is completed.
- Fixed 48 kHz mixdown (no selectable sample rate yet).
- No audio clip looping or time-stretching.
- No independent MIDI tracks or MIDI file interchange.
- No selectable device buffer sizes.
- No effects, automation, or plugin hosting.
- Demo / illustrative content must not be confused with real session state.

---

## Recommendation for merge

PR #33 is large and valuable. It should be merged only when:

1. Automated evidence (CI + unit/integration tests) is green on the final head, **and**
2. At least the “Basic playback & transport” + “HypnoSynth” + “Session persistence” hardware checks have been performed and recorded (even if only on one Windows machine).

If hardware verification cannot be completed immediately, keep the PR open or merge with an explicit “hardware verification still pending” note in the merge commit / release notes. Do not silently treat CI green as proof of real-world audio correctness.

---

## How to record results

When you complete any hardware check, add a short note to the PR (or to this file in a follow-up commit):

```
Date:
Machine / Windows version:
Output device:
Build (commit SHA + Release/Debug):
Result: (pass / fail + brief observation)
```

This keeps the distinction between “code exists” and “we actually heard it” honest for future contributors.

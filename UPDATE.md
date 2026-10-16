# Aetherband — Update Log

Chronological record of meaningful changes. Newest entries first.

---

## 2026-10-16 (evening) — UI overhaul + precise waveforms

**Status:** Early alpha. Transport Stop fixed. Desktop UI redesigned toward a Logic/Ableton-like dark pro layout with real waveform peaks.

### Summary

Full visual pass on the Avalonia desktop shell while keeping Play / Pause / Stop, track load/remove, volume, pan, mute, master, meters, and device selection working. Track lanes now show **precise peak waveforms** generated offline from the audio file, with a live playhead driven by engine telemetry.

### UI changes

| Area | Change |
|------|--------|
| Branding | Window title, top bar, status bar → **Aetherband** (no RouletteStudio chrome) |
| Theme | Forced dark Fluent theme; denser layout, quieter borders, pro color palette |
| Transport | Centered transport cluster with large time readout |
| Arranger | Cleaner track rows; waveform lane replaces solid placeholder |
| Master | Slimmer master strip with stereo meters + vertical fader |
| Empty state | Clear “No tracks” CTA |

### Waveforms

| Component | Role |
|-----------|------|
| `Controls/WaveformControl.cs` | Custom Avalonia control — draws mirrored peak columns + playhead |
| `Services/PeakGenerator.cs` | Offline peak extraction via **NAudio** (WAV/AIFF/MP3 + MediaFoundation for other formats on Windows) |
| `TrackViewModel` | `Peaks`, `Progress`, `IsGeneratingPeaks` |
| `MainViewModel` | Generates peaks async on load; pushes `TimelineProgress` into each lane |

Peaks are absolute magnitudes in `[0, 1]` at 2048 horizontal buckets by default. Generation runs off the UI thread.

### Dependency

- Added NuGet package `NAudio` 2.2.1 for offline peak decoding only (not on the real-time audio path).

### Still deferred

- Timeline zoom / horizontal scroll
- Scrub-to-seek (click waveform to seek — needs full seek/decoder restart)
- Project save/load, recording, export
- C# namespace / project folder rename (`RouletteStudio.*`)

### How to try it

```powershell
git pull origin main
powershell -ExecutionPolicy Bypass -File .\tools\run.ps1
```

Load audio → waveform should appear after a short background generate. Play → white playhead moves across the lane.

---

## 2026-10-16 — Transport Stop fix, naming cleanup, and documentation

**Status:** Early alpha. Phase 1–3 implemented. Stop transport bug (issue #5) fixed in core and confirmed by the owner at runtime.

### Summary

The main transport defect reported in issue #5 (Stop reset the playhead but audio continued / did not restart correctly from the beginning) was diagnosed and fixed. Supporting documentation, workspace metadata, and naming were also cleaned up.

### What was wrong

- `EngineCommand::Stop` only set `is_playing = false`, zeroed the playhead, and drained the TrackPlayer ring-buffer consumers.
- Background `StreamDecoder` workers were **not** rewound. Draining the consumer side does not seek the file source.
- Result: after Stop, the next Play could continue mid-file or behave inconsistently. Earlier partial fixes that only touched the audio-thread side were insufficient.

### What was changed (core transport)

| Area | Change |
|------|--------|
| `core/src/ringbuf.rs` | Added `EngineCommand::RestartTrack { track_id, consumer_ptr }` so the control thread can hand a fresh decoder consumer to an existing TrackPlayer. |
| `core/src/track.rs` | Added `TrackPlayer::replace_stream()` — swaps the stream consumer and resets the playback cursor while preserving gain / pan / mute. |
| `core/src/audio.rs` | Handles `RestartTrack`. Added regression test `stop_silences_output_and_resets_playhead`. Fixed missing `DecodedBlock` import (E0425). |
| `core/src/lib.rs` | `DAWEngine::stop()` now pushes Stop **and** restarts every live `StreamDecoder` from the start of its file, then delivers the new consumers via `RestartTrack`. |

**Protocol after the fix:**

1. Control thread pushes `Stop`.
2. Audio thread sets `is_playing = false`, playhead = 0, resets track consumers.
3. Control thread stops old decoders, spawns new ones from frame 0, pushes `RestartTrack` for each track.
4. Next Play consumes audio from the beginning of each file.

### Verification

- **Automated:** Regression test asserts Play produces non-silence, then Stop produces silence and telemetry reports `is_playing = false` / `playhead_frame = 0`.
- **Runtime (owner):** Confirmed fixed after rebuild (`cargo` / desktop app). Stop now silences correctly.

### Naming and metadata cleanup

- Root `Cargo.toml`: authors and `repository` updated to Aetherband / current GitHub URL (removed old RouletteStudio / arpeggi1 references).
- C-ABI and core library comments: RouletteStudio → Aetherband.
- README: added explicit **Tech Stack** table; noted that the desktop project folder and some C# namespaces still use the legacy name `RouletteStudio` (functional rename deferred).
- Issue #5: detailed comment describing the root cause and the fix.

### Related earlier work on the same day (before the Stop fix)

- Documentation alignment across README, ROADMAP, VISION, REQUIREMENTS, ARCHITECTURE, AUDIO_ENGINE, API_CONTRACT, DECISIONS, AI_WORKFLOW (PR #6).
- Windows build/run script fixes (PR #4).
- Phase 1–3 stabilization: EOF terminal marker, verification scripts, .NET CI path fixes (PR #3).
- Agent instructions, PR template, ruleset documentation (PR #2).

### Commits (Stop fix cluster, newest first)

| Time (UTC) | Commit | Message |
|------------|--------|---------|
| 21:57 | `fd97cda` | fix: import DecodedBlock in audio.rs (fixes E0425 compile error) |
| 21:52 | `5d17807` | docs: clarify full tech stack and note Stop transport fix (issue #5) |
| 21:52 | `4e8a36e` | chore: rename RouletteStudio → Aetherband in C-ABI comments |
| 21:51 | `752fad3` | chore: update workspace metadata to Aetherband |
| 21:51 | `b446b1d` | fix(transport): restart StreamDecoders on Stop so Play begins from the start of each file |
| 21:50 | `b6b87d5` | fix(transport): handle RestartTrack and add Stop→silence regression test |
| 21:49 | `88118ca` | fix(transport): add TrackPlayer::replace_stream for decoder restart on Stop |
| 21:48 | `8bb84ad` | fix(transport): add RestartTrack command for proper Stop/Play restart of decoder streams |

### Current roadmap position

| Phase | Status |
|-------|--------|
| 0 – Architecture & documentation | Complete |
| 1 – Real-time audio core | Complete |
| 2 – File playback & streaming | Complete (Stop fixed) |
| 3 – Multi-track mixer + timeline UI | UI overhaul + waveforms |
| 3.5 – Stabilization gate | Stop fixed + regression test; runtime confirmed |
| 4 – Recording, project save/load, export | Next |
| 5 – MIDI + instruments | Planned |
| 6 – Effects + plugin hosting | Planned |

### Still known / deferred

- Desktop project folder and C# namespaces still named `RouletteStudio` (cosmetic).
- No project save/load, recording, or export yet.
- Device switching while tracks are loaded still needs deeper lifecycle testing.
- Seek is not yet a full sample-accurate restart of decoder position.

### How to build and run

```powershell
# From repo root (Windows)
powershell -ExecutionPolicy Bypass -File .\tools\build.ps1
powershell -ExecutionPolicy Bypass -File .\tools\run.ps1

# Tests
cargo test -p daw_core
```

---

*This file is the human-readable change log. For engineering risk notes and verification checklists see `docs/ENGINEERING_STATUS.md` and `docs/ROADMAP.md`.*

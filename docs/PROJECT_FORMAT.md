# Project File Format Specification: CustomDAW

## 1. Overview & Objectives

The CustomDAW project file format (`.dawproject`) is designed to fulfill four primary criteria:
1. **Portability:** A project created on Windows must open identically on macOS (and on the future mobile companion DAW for iOS/Android).
2. **Self-Containment:** A project must bundle its audio assets to eliminate the common DAW plague of "Missing Audio File" errors when moving between computers.
3. **Resilience & Versioning:** Upgrading the DAW must never break older projects, and schema changes must be versioned explicitly.
4. **Fast Loading & Autosave:** Saving a project must never block audio playback or freeze the user interface.

---

## 2. Container Structure: The Bundled `.dawproject`

A `.dawproject` file is a standard ZIP archive containing human-readable JSON metadata, binary cache data, and raw media:

```
MySong.dawproject (ZIP archive)
├── project.json            # Master project definition (Timeline, Tracks, Mixer, BPM)
├── assets/                 # Embedded audio recordings and imported samples
│   ├── recording_01.wav    # 24-bit 48kHz WAV
│   └── vocal_take_02.wav   # 24-bit 48kHz WAV
├── cache/                  # Ephemeral data (can be deleted without losing audio)
│   └── waveforms.bin       # Pre-computed multi-resolution peak cache for fast rendering
└── history/                # Autosave and recovery checkpoints
    └── autosave_last.json  # Snapshot before crash/unexpected shutdown
```

---

## 3. Metadata Schema (`project.json`)

```json
{
  "$schema": "https://customdaw.org/schema/v1/project.json",
  "version": "1.0.0",
  "meta": {
    "title": "Acoustic Session",
    "artist": "Jane Doe",
    "created_at": "2026-10-16T19:00:00Z",
    "modified_at": "2026-10-16T19:30:00Z",
    "sample_rate": 48000,
    "tempo_bpm": 120.0,
    "time_signature": [4, 4]
  },
  "master_bus": {
    "volume_db": -0.5,
    "pan": 0.0,
    "is_muted": false
  },
  "tracks": [
    {
      "id": "trk_01",
      "name": "Acoustic Guitar",
      "color_hex": "#4A90E2",
      "volume_db": -2.0,
      "pan": -0.2,
      "is_muted": false,
      "is_soloed": false,
      "clips": [
        {
          "id": "clip_01",
          "name": "Guitar Intro",
          "asset_path": "assets/recording_01.wav",
          "timeline_start_samples": 0,
          "source_offset_samples": 0,
          "duration_samples": 384000,
          "fade_in_samples": 240,
          "fade_out_samples": 480,
          "gain_db": 0.0
        }
      ]
    }
  ]
}
```

---

## 4. Save and Load Mechanics

### 4.1 Non-Blocking Autosave
- Saving is performed entirely on a background worker thread.
- The UI takes an immutable snapshot of the project state (`ProjectViewModel.ToSnapshot()`).
- The worker thread writes the JSON file and updates the zip bundle asynchronously without any impact on the audio callback.

### 4.2 Crash Recovery
- Every 60 seconds (configurable), the worker thread writes a temporary `autosave_last.json` checkpoint into the local application cache directory.
- If the application crashes, the next startup detects the orphan recovery file and offers the user: *"CustomDAW recovered unsaved changes from your last session. Restore?"*

---

## 5. Cross-Platform Compatibility (Desktop & Future Mobile)

- **Relative Paths:** All asset references inside `project.json` use normalized forward-slash relative paths (e.g., `assets/vocal.wav`). No Windows drive letters (`C:\`) or absolute Unix paths (`/Users/...`) are ever serialized.
- **Sample-Accurate Positioning:** Timeline positions are recorded in absolute sample indices (`samples = seconds * sample_rate`), eliminating floating-point rounding errors across different hardware architectures.
- **Mobile Compatibility:** When the mobile companion DAW opens a desktop project, it reads the identical `project.json` and loads the same audio assets without conversion.

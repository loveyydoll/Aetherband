# Aetherband native session format — Alpha v5

**Implemented in:** `apps/desktop/lib/src/session_store.dart` and the Flutter File menu.  
**Extension:** `.aetherband.json` (JSON, UTF-8).  
**Status:** Early-alpha imported-audio session format; not yet a portable production project bundle.

## What this version actually saves

A v5 document saves the session title, imported audio tracks and regions, mixer state, performance settings, and one HypnoSynth arrangement track with its own gain, pan, mute and solo state. The 16-step note/rest phrase remains session-wide. Native engine IDs are allocated afresh when reopening and never appear in the document. Versions 1 through 4 remain readable; missing solo, clip-position and instrument-track fields default to off, zero or empty respectively.

```json
{
  "format": "aetherband-session",
  "schemaVersion": 5,
  "title": "My Song",
  "performance": {
    "tempo": 120.0,
    "metronome": false,
    "sequence": false,
    "master": 0.8,
    "preset": 0,
    "macros": [0.5, 0.5, 0.5, 0.5, 0.5]
  },
  "tracks": [
    {
      "id": "native-stable-001",
      "name": "Guitar",
      "sourceUri": "file:///C:/Music/guitar.wav",
      "gain": 0.8,
      "pan": 0.5,
      "muted": false,
      "solo": false,
      "startSeconds": 2.5,
      "regions": [
        {
          "id": "native-stable-001-clip",
          "startSeconds": 2.5,
          "sourceStartSeconds": 0.0,
          "durationSeconds": 4.25
        }
      ]
    }
  ],
  "instrumentTracks": [
    {
      "id": "hypno-1",
      "name": "HypnoSynth",
      "gain": 0.8,
      "pan": 0.5,
      "muted": false,
      "solo": false
    }
  ]
}
```

The app validates schema version, object fields, globally unique track/region IDs, at most one HypnoSynth instrument track, parameter ranges, total track count (maximum 64), audio region count (maximum 64) and local-file URI format. The document has a 2 MiB size limit. Opening preflights the referenced audio paths. Unsupported versions, malformed JSON or unavailable source audio raise visible errors instead of loading an incomplete session.

## Save and reopen

* Save and Save As use a native file picker, writing JSON on a worker isolate.
* Existing projects are written to a flushed temporary file in the destination directory. The old document is moved to a `.bak` fallback before replacement; opening the expected path also supports recovery from an existing `.bak` when the main file is missing. The app does **not** yet present a backup browser/recovery wizard.
* Open validates the document first, builds a new native engine, imports the files, restores mixer parameters, then swaps the workspace's active engine. A failed staged import does not intentionally remove the previous session.
* New Session creates an empty real-audio inventory after confirmation about unsaved changes.
* The title bar marks unsaved audio, instrument-track and mixer changes.

## Explicit non-features

* Local audio files are **referenced, not embedded or copied**. Do not move them after saving; cross-computer portability and relinking are not implemented.
* The existing demo clips remain visualization-only and are not saved. Imported audio clips snap to quarter-note beats while moved with transport stopped at its start; the Region menu splits, joins and trims selected audio regions at the stopped playhead. Source offsets and durations are applied by native playback and retained in the session.
* This format does **not** save recorded audio, independent MIDI regions or note editing, automation, plugins, device configuration, undo history, or mastered output. HypnoSynth performance settings, including its editable 16-step note/rest sequence, and the single instrument track's mixer state are saved. MIDI file interchange is not implemented.
* This is still an early-alpha session save/open workflow, not a stable project-compatibility commitment.
* Atomic replacement semantics depend on filesystem behavior; especially after power loss, manual recovery from `.bak` may be necessary. Project writes are not a substitute for versioned backups.

## Future direction

Do not reuse `.dawproject` for Aetherband's native JSON format: DAWproject is an existing interchange standard. Consider a versioned native bundle with relative media paths and internal assets after the session model, real clip scheduling and export are established.

## Verification

Run `flutter analyze` and `flutter test` (including `session_store_test.dart` and the File-menu widget test), then verify Windows file dialogs and native reopen on real audio hardware. CI success does not establish disk durability across abrupt power loss.

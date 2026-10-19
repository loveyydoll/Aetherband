# Aetherband native session format — Alpha v3

**Implemented in:** `apps/desktop/lib/src/session_store.dart` and the Flutter File menu.  
**Extension:** `.aetherband.json` (JSON, UTF-8).  
**Status:** Early-alpha imported-audio session format; not yet a portable production project bundle.

## What this version actually saves

A v3 document saves the session title, ordered imported audio tracks, stable persistent track IDs, local file URIs, display names, track gain, pan, mute and solo settings, clip start positions, and HypnoSynth/performance settings. Native engine IDs are allocated afresh when reopening and never appear in the document. Version 1 and version 2 files remain readable; missing solo and clip-position fields default to off and zero respectively.

```json
{
  "format": "aetherband-session",
  "schemaVersion": 3,
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
      "startSeconds": 2.5
    }
  ]
}
```

The app validates schema version, object fields, unique IDs, parameter ranges, track count (maximum 64) and local-file URI format. The document has a 2 MiB size limit. Opening preflights the referenced audio paths. Unsupported versions, malformed JSON or unavailable source audio raise visible errors instead of loading an incomplete session.

## Save and reopen

* Save and Save As use a native file picker, writing JSON on a worker isolate.
* Existing projects are written to a flushed temporary file in the destination directory. The old document is moved to a `.bak` fallback before replacement; opening the expected path also supports recovery from an existing `.bak` when the main file is missing. The app does **not** yet present a backup browser/recovery wizard.
* Open validates the document first, builds a new native engine, imports the files, restores mixer parameters, then swaps the workspace's active engine. A failed staged import does not intentionally remove the previous session.
* New Session creates an empty real-audio inventory after confirmation about unsaved changes.
* The title bar marks unsaved imported-audio and mixer changes.

## Explicit non-features

* Local audio files are **referenced, not embedded or copied**. Do not move them after saving; cross-computer portability and relinking are not implemented.
* The existing demo clips remain visualization-only and are not saved. Imported audio clips can be moved while the transport is stopped at its start; native playback scheduling and the clip start position are saved together.
* This format does **not** save recorded audio, instrument/MIDI regions, automation, plugins, device configuration, undo history, or mastered output. HypnoSynth performance settings are saved, but its generated phrase is a performance option rather than editable MIDI.
* This is still an early-alpha audio-session save/open workflow, not a stable project-compatibility commitment. MIDI and instrument regions are not saved.
* Atomic replacement semantics depend on filesystem behavior; especially after power loss, manual recovery from `.bak` may be necessary. Project writes are not a substitute for versioned backups.

## Future direction

Do not reuse `.dawproject` for Aetherband's native JSON format: DAWproject is an existing interchange standard. Consider a versioned native bundle with relative media paths and internal assets after the session model, real clip scheduling and export are established.

## Verification

Run `flutter analyze` and `flutter test` (including `session_store_test.dart` and the File-menu widget test), then verify Windows file dialogs and native reopen on real audio hardware. CI success does not establish disk durability across abrupt power loss.

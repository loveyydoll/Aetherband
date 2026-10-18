# Aetherband native session format — Alpha v1

**Implemented in:** `apps/desktop/lib/src/session_store.dart` and the Flutter File menu.  
**Extension:** `.aetherband.json` (JSON, UTF-8).  
**Status:** Early-alpha imported-audio session format; not yet a portable production project bundle.

## What this version actually saves

A v1 document saves the session title, order of real imported audio tracks, stable persistent track IDs, local file URIs, display names, and track gain, pan and mute settings. Native engine IDs are allocated afresh when reopening and never appear in the document.

```json
{
  "format": "aetherband-session",
  "schemaVersion": 1,
  "title": "My Song",
  "tracks": [
    {
      "id": "native-stable-001",
      "name": "Guitar",
      "sourceUri": "file:///C:/Music/guitar.wav",
      "gain": 0.8,
      "pan": 0.5,
      "muted": false
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
* The existing demo clips remain visualization-only. They are not saved. Real imported clips currently begin at timeline zero; their visual editing is still disabled because the native clip scheduler does not yet support repositioning.
* This format does **not** save recording, instruments, MIDI, automation, plugins, device configuration, undo history, or mastered output.
* The main app currently supports only an initial audio-only project save/open workflow. It is not yet a stable project-compatibility commitment.
* Atomic replacement semantics depend on filesystem behavior; especially after power loss, manual recovery from `.bak` may be necessary. Project writes are not a substitute for versioned backups.

## Future direction

Do not reuse `.dawproject` for Aetherband's native JSON format: DAWproject is an existing interchange standard. Consider a versioned native bundle with relative media paths and internal assets after the session model, real clip scheduling and export are established.

## Verification

Run `flutter analyze` and `flutter test` (including `session_store_test.dart` and the File-menu widget test), then verify Windows/macOS file dialogs and native reopen on real audio hardware. CI success does not establish disk durability across abrupt power loss.

# Changelog

All notable changes to Aetherband are recorded here. This is a development changelog, not a substitute for Git tags or GitHub Releases. Dates below identify the merge date of the relevant pull request unless explicitly stated otherwise.

## [Unreleased]\n\n### Architecture and documentation\n\n- **2026-10-19 — Native C++/JUCE direction:** Accepted ADR-008, making C++20+ and JUCE the committed application foundation, with CMake and Windows/macOS as required targets. Aetherband owns DSP graph execution, processor lifecycle, routing, transport, and offline-rendering semantics.\n- **2026-10-19 — Documentation overhaul:** Aligned the current README, architecture, vision, project state, migration plan, roadmap, feature tracker, audio-engine contract, project-format notes, contributor/agent guidance, and technology-stack guidance.\n- **Migration safety:** Rust/C ABI/Flutter/Dart are retained as legacy references until the native replacement meets acceptance criteria; they are not the target architecture.\n\n## [Unreleased]

### Added

- **2026-10-18 — Audio session persistence (pending merge):** Added a versioned early-alpha `.aetherband.json` format for imported audio source paths and stable track IDs, plus mixer gain/pan/mute settings. The File menu now supports Save, Save As, Open and New Session; project reads/writes run off the UI isolate. Open validates files before staging a new native engine, avoiding destructive partial session replacement. Demo clips, real clip editing and bundled assets remain unimplemented.

- **2026-10-18 — Native mixer controls (pending merge):** Connected imported track gain, pan, and mute controls from the Flutter mixer and timeline through the existing native C ABI. Added UI and native integration regressions; physical audio verification remains pending.

- **2026-10-17 — PR #22, Engine foundation:** Added a typed, control-thread audio graph model with Audio, Control, Event, and Analysis signal kinds; port/channel compatibility validation; cycle rejection; and topological ordering. This is graph metadata and validation only; it is not yet executed by the real-time audio callback.
- **2026-10-17 — PR #22, Audio import:** Added desktop file selection and connected imported audio files to the native decoder/track engine. Added Dart FFI/controller operations for loading, removing, and counting native tracks.
- **2026-10-17 — PR #22, Regression coverage:** Added a Rust regression test for Pause silence and Play resume.
- **2026-10-17 — PR #21, Engine audit:** Added an engine-foundation audit covering current architecture, risks, and implementation priorities.
- **2026-10-17 — PR #14, Spatial foundations:** Added spatial-audio metadata types for channel layouts and Cartesian source positions. These types are not connected to playback or project persistence.
- **2026-10-17 — PR #14, Stereo utility:** Added an allocation-free equal-power stereo gain utility with deterministic tests for hard-left, centre, hard-right, and invalid inputs.
- **2026-10-17 — Creative-engine planning:** Added the architecture plan for a shared creative engine, visual programming, extensible synthesis, and staged spatial-audio work.
- **2026-10-17 — Release process:** Added a policy distinguishing commits, merged pull requests, and published releases.

### Changed

- **2026-10-17 — PR #22, Device switching:** Rebuilds the replacement audio processor and command queues for the selected sample rate, prepares decoder workers for that rate, and re-installs existing track IDs rather than switching to an empty processor.
- **2026-10-17 — PR #22, Track state:** Preserves each existing track's gain, pan, and mute settings when rebuilding the audio pipeline during device switching.
- **2026-10-17 — PR #22, Capacity guard:** Enforces the engine's fixed maximum track count when importing tracks.
- **2026-10-17 — PR #20, Desktop UI documentation:** Clarified that Flutter is the intended primary desktop UI, and documented the current native ABI/sample-rate-query status and remaining end-to-end verification.
- **2026-10-17 — PR #19, Native boundary:** Aligned Dart FFI with the versioned C ABI, including sample-rate querying and lifecycle/state handling; removed misleading UI states that implied unavailable native functionality was working.
- **2026-10-17 — PR #12, Frontend migration:** Merged the desktop frontend migration from the retired C#/Avalonia direction to Flutter with Dart FFI and the Rust engine.

### Fixed

- **2026-10-17 — PR #22, Device-switch queue loss:** Recreates the command queues and re-registers existing tracks during device switching, preserving track IDs and stored gain/pan/mute values.
- **2026-10-17 — PR #19, FFI contract:** Corrected the Dart/native contract and lifecycle handling to match the versioned C ABI.
- **2026-10-17 — Transport regression coverage:** Added explicit Pause/resume coverage while retaining the existing Stop/rewind regression test.

### Known limitations

- A successful CI build does not prove that real audio hardware behaves correctly on every machine. Manual device switching and playback testing is still required.
- Imported timeline clip width is a placeholder; native audio duration is not yet exposed to the UI.
- The UI still contains illustrative demo tracks.
- The typed graph model is not yet connected to the real-time processing callback; arbitrary graph DSP, instruments, effects, routing, and a complete plugin system are not delivered by this work.
- Do not treat audio recording, full timeline editing, project save/reopen, MIDI editing, automation, plugin hosting, spatial rendering, or export as complete unless separately verified.
- These changes remain part of the unreleased early-alpha development line. No version or release date is implied by these entries.

## Release history

No tagged or published Aetherband release has been recorded in this changelog yet. Development milestones and merged pull requests are not releases by themselves.

## Entry format

For each published version, add a dated section such as:

`## [0.1.0-alpha.1] - YYYY-MM-DD`

Include **Added**, **Changed**, **Fixed**, **Removed**, and **Known limitations** as appropriate. Link the version to its Git tag and GitHub Release when those exist. Never backdate a release to the date of a commit or PR merge.

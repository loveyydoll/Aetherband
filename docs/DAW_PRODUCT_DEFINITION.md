# Aetherband DAW Product Definition

**Status:** Product requirements and implementation guide  
**Applies to:** Windows-first desktop development  
**Architecture decision:** Flutter/Dart is the primary desktop UI; Rust owns the audio engine and DSP; a versioned C ABI connects them through Dart FFI. Do not replace this architecture without an explicit owner decision.

This document defines what Aetherband must do to qualify as a useful digital audio workstation (DAW), how to distinguish real functionality from a prototype, and how to prioritize future work. It is not a claim that every listed capability is implemented today.

## 1. What a DAW is

A DAW is an integrated environment for creating, recording, editing, arranging, processing, mixing, saving, and exporting audio and/or musical performances. Its core value is the complete, dependable workflow between an initial idea and a finished audio deliverable—not the number of controls or the visual resemblance to another application.

Aetherband should support both audio-first production and instrument/pattern-based composition. Its distinctive sound-design tools and visual identity should build on a dependable DAW foundation rather than replace it.

## 2. Core production workflow

A user should ultimately be able to complete this workflow without leaving the application:

1. Create a project or open an existing one.
2. Import audio and create audio or instrument tracks.
3. Record audio from a selected input, or enter/play musical notes and patterns.
4. Arrange clips and patterns against a timeline, tempo, and meter.
5. Edit timing and regions without destroying the original source.
6. Play the arrangement reliably while adjusting track and master levels.
7. Shape sound with instruments, effects, and automation.
8. Save, close, and reopen the project with its content and settings intact.
9. Export a correctly timed, listenable mix to a documented audio format.
10. Recover sensibly from missing media, unavailable devices, invalid input, and failed operations.

The workflow should remain useful with a small project and scale to larger sessions without freezing the audio callback or making basic editing unreliable.

## 3. DAW capability areas

### A. Project and session management — foundational

- New, Open, Save, and Save As with clear unsaved-change behavior.
- A versioned session format with stable track/clip identities, project settings, tempo/meter, mixer state, instrument settings, regions, and supported automation.
- Safe validation before replacing the currently open session.
- Reopen round-trip tests and clear handling of missing or moved media.
- No silent data loss; backups or recovery mechanisms should be added before production use.

### B. Audio engine and transport — foundational

- Reliable Play, Pause, Stop/Return to Start, seek, loop/loop-region support, and accurate transport state.
- Consistent sample-rate conversion, channel mapping, timing, and predictable handling of device changes and stream failures.
- No blocking file I/O, UI calls, unbounded work, or avoidable allocations in the real-time audio callback.
- Bounded communication between UI/control threads and the engine, explicit ownership, and safe shutdown.
- Metronome and tempo/meter behavior must agree with the visible ruler and musical grid.

### C. Tracks and arrangement — foundational

- Create, rename, reorder, duplicate, mute, solo, and remove tracks with clear selection and focus.
- A timeline ruler, tempo/meter display, playhead, horizontal zoom/scroll, snapping toggle, and meaningful empty states.
- Audio regions with visible duration/waveform where supported; move, trim, split, join, copy, cut, paste, duplicate, and delete.
- Source-bounded, non-destructive editing: regions refer to source media and offsets rather than rewriting the original file.
- Undo/redo must reverse edits in chronological order and keep UI, session data, and engine state consistent.
- Pattern/instrument regions must have a clear relationship to tempo, meter, and the transport.
- Large sessions should use bounded/virtualized UI rendering where needed.

### D. Recording and media handling — core DAW capability

- Select and identify input/output devices; show meaningful errors when devices are absent or unavailable.
- Arm a track, record from input, stop safely, finalize the file, and add the recorded media to the session.
- Clearly communicate recording state, elapsed time, and failures. Protect against buffer overflow, device disconnect, and incomplete file finalization.
- Import common audio formats based on actual decoder support; unsupported formats must be reported honestly.
- Test real hardware separately from unit tests and CI. A successful build is not proof that a microphone or speaker works.

### E. Musical composition and instruments — essential for Aetherband's direction

- A built-in instrument with dependable note triggering, release/panic behavior, presets, and project persistence.
- A reusable MIDI/event model that can represent notes, duration, velocity, and timing, rather than treating one fixed pattern as the entire MIDI system.
- Editable patterns/regions and eventually a piano roll, MIDI input/recording, multiple independent instrument tracks, and standard MIDI file import/export.
- Deterministic scheduling aligned to the transport, tempo, meter, and audio clock.
- Aetherband's original instruments and sound-design workflow should be developed as a differentiator.

### F. Mixing — core DAW capability

- Per-track gain, pan, mute, solo, and master output controls with predictable interaction.
- Audible and useful level meters, clipping awareness, and consistent handling of mute/solo combinations.
- A documented signal-flow model: track source/instrument → track processing → mixer/master → output/export.
- Offline mixdown should use the intended project signal flow and match arrangement timing. Tests should verify signal, channel layout, sample rate, bit depth, duration, and error behavior.
- Bus/group routing can follow the basic mixer, but should not be architected out of the engine.

### G. Effects and automation — required for a mature DAW, staged after the basics

- A coherent effect-processing model and parameter interface.
- Track/parameter automation with defined time units, interpolation, playback scheduling, persistence, and undo/redo.
- Effects and automation must render consistently in live playback and offline export.
- Plugin hosting should be a later, deliberate project with format/licensing review, compatibility testing, and fault isolation. Do not claim plugin support merely because the architecture has a graph model.

### H. Export and delivery — core DAW capability

- Render the arrangement to a user-selected destination with clear format settings and progress/cancel/error states where feasible.
- Preserve clip offsets, trim ranges, tempo-based placements, sample-rate conversion, stereo/channel layout, and the intended mix.
- Never silently overwrite an existing file or leave a corrupt destination on failure.
- Test exported files by reopening/decoding them and checking duration and non-silent signal, not only their header fields.
- Later work may add stems, track export, and Bounce in Place.

### I. Usability and workflow — required across all features

- A music-production workspace, not a generic dashboard or splash screen: transport, timeline, track controls, mixer access, and File/Edit/Track/Region/View/Help menus should be discoverable.
- Keyboard shortcuts, contextual actions, tooltips, sensible selection/focus, accessible labels, scalable layout, and useful empty/error/loading states.
- No decorative demo clips or fake controls that appear functional. Mark experimental or unavailable functionality explicitly.
- Editing should feel immediate while heavy decoding, disk operations, session loading, and export work outside the UI thread.
- Provide useful error messages and a way to reproduce/report failures.

## 4. Current implementation snapshot (PR #33 branch)

This is a source/PR-based snapshot, not an independent local build or hardware certification. Update it as code changes and verify each item on the current branch before treating it as release evidence.

### Present in the code / reported by the PR

- Rust native audio engine and versioned C ABI, with Flutter/Dart FFI integration.
- Windows playback and multi-track mixing controls.
- HypnoSynth with presets, live note input, and an editable 16-step phrase.
- Audio import and source-bounded region editing, including trim/split/join and timeline operations described by the PR.
- Session persistence with versioned schema and older-schema read paths.
- Windows input-recording path writing stereo PCM24 WAV.
- Offline stereo PCM24 mixdown at fixed 48 kHz, including resampling.
- Timeline tempo/meter features and scheduled pattern regions.
- Rust, ABI, Dart, widget, and Windows CI tests are reported by the PR.

### Must still be validated in real use or expanded

- Physical speaker/headphone output and microphone/line-in capture.
- Long-duration recording, device disconnection/recovery, dropped-frame handling, and file finalization.
- Full save/close/reopen workflows with missing media and larger projects.
- Export parity with live playback, trims/regions, meter/tempo behavior, and error/overwrite cases.
- Audio format support beyond the formats actually tested; WAV success does not prove MP3, FLAC, or other formats work.
- General MIDI event editing, piano roll, independent MIDI tracks, MIDI file interchange, and richer instrument workflows.
- Effects, automation, buses/routing, plugin hosting, looping/time-stretching, stems, and Bounce in Place.
- Sustained real-world performance, accessibility, recovery, and usability.

The implementation status must be confirmed from current source and tests. Never convert a PR description or planned feature into a verified claim without evidence.

## 5. Recommended implementation order

### P0 — Make the current end-to-end path trustworthy

1. Verify playback, import, recording, save/reopen, editing, undo/redo, and mixdown on Windows.
2. Add regression tests for session round trips, region source bounds, undo/redo ordering, transport state, export duration/signal, and failed operations.
3. Exercise recording on real input hardware, including long takes, disconnects, buffer overflow reporting, and safe finalization.
4. Fix lifecycle hazards: repeated engine open/close, shutdown during recording/export, device switching, and full command queues.
5. Make the UI accurately reflect engine state and errors; remove any remaining fake success/demo behavior.

### P1 — Complete the everyday audio workflow

1. Improve track management, selection, timeline navigation, waveform readability, and editing consistency.
2. Make audio format support explicit and test each claimed decoder format.
3. Add reliable loop/loop-region behavior and clarify whether trim, split, join, copy/paste, and undo work for every region type.
4. Improve mixer metering and document signal flow.
5. Validate project media paths, backups/recovery, and non-destructive project persistence.

### P2 — Make composition a real system

1. Generalize the fixed phrase into a reusable MIDI/event model.
2. Add independent instrument/MIDI tracks and region-level note editing.
3. Add piano-roll editing, note duration/velocity, MIDI input/recording, and standard MIDI file interchange.
4. Strengthen instrument preset persistence, timing, polyphony, and performance controls.

### P3 — Approach mature production capability

1. Add native effects and a defined routing/signal-flow model.
2. Add parameter automation and ensure playback/export parity.
3. Evaluate plugin hosting only after engine, state, crash isolation, licensing, and compatibility requirements are documented.
4. Add stems/Bounce in Place and advanced production tools as justified by real workflows.

## 6. Definition of done for a DAW feature

A feature is not done just because it compiles or has a visible button. It is done when:

- The user can reach it through the Flutter UI and understand its state.
- The UI communicates success and failure honestly.
- The Rust engine performs the real operation through the documented C ABI.
- Session persistence stores and restores relevant state.
- Undo/redo behaves correctly where the operation is editable.
- Tests cover normal, boundary, and failure cases.
- Real-time callback safety and resource ownership are preserved.
- Windows CI passes and relevant manual audio-hardware checks are recorded.
- Documentation distinguishes implemented, automated-tested, hardware-verified, experimental, and planned behavior.

## 7. Non-negotiable architecture and product rules

- Flutter is the primary full-scale desktop UI. Do not reintroduce a C# frontend or create a parallel frontend without an explicit owner decision.
- Rust remains responsible for audio processing and real-time behavior. Keep the UI out of the audio callback.
- Use the versioned C ABI as the supported boundary; keep Dart declarations, native exports, ownership, and error codes in sync.
- Windows is the current validation target. Do not silently reintroduce a macOS requirement into this immediate milestone.
- Keep the project free/open source according to its existing project license and review dependencies and licenses before adopting code or plugins.
- Preserve Aetherband's own identity and original instruments. Inspiration from other DAWs should inform workflow quality, not copy their branding or interface wholesale.
- Reliability, honest status, data integrity, and an end-to-end musical workflow take priority over adding a large feature count.

## 8. What “DAW-ready” should mean

Aetherband should not be called production-ready until a musician can repeatedly create or open a session, import and record audio, arrange and edit clips, use instruments, mix, save/reopen without loss, and export a correct deliverable on the supported Windows setup—with documented limitations and no known critical data-loss or audio-safety defects.

This is a quality bar, not a release date.

# Aetherband Product and Engineering Roadmap

**Last reviewed:** 2026-10-17  
**Status:** Planning document; check linked source, tests and GitHub Actions before treating any implementation as verified.  
**Product direction:** Flutter/Dart is the mandatory full-scale desktop UI, using Dart FFI over the existing Rust C ABI. Rust remains the audio engine. C#/Avalonia is transitional and is expected to be retired after feature parity and owner approval.

This is the broad backlog for making Aetherband a dependable, full-featured desktop DAW. It intentionally separates **foundation work**, **minimum real-audio Flutter parity**, **core DAW workflows**, **creative production features**, and **release engineering**. A feature shown in the mock UI is not complete until its data path, failure behavior, tests and user documentation exist.

## Guiding rules

1. **Flutter is the destination, not a prototype-only experiment.** Work through platform, FFI, UI and packaging problems instead of reverting to a permanent C# UI.
2. **Keep Rust native.** Device callbacks, decoding, DSP, mixing, real-time scheduling and audio buffers stay in Rust/native code.
3. **C ABI is the stable boundary.** New UI needs that exceed the current ABI must be added deliberately, with documented ownership, thread safety, errors and tests. Dart must not reach into private Rust internals or call C# bindings.
4. **Never fake completion.** A control should work, be clearly disabled as not implemented, or explain the limitation. No mock transport, synthetic waveform, fake meter or local-only state in production mode.
5. **Real-time safety outranks convenience.** No blocking I/O, UI callbacks, locks, allocations, unbounded logging or waiting in the audio callback. Use bounded queues and explicit backpressure.
6. **Ship one primary UI.** Keep Avalonia as the migration fallback; retire it only after documented parity and owner approval. Do not maintain two permanent frontends by default.
7. **Each milestone needs evidence.** Automated tests, Windows/macOS builds, manual audio checks where hardware is required, and clear documentation of what was actually tested.

## Status vocabulary

- **Existing / reported:** source or maintainer report indicates the feature exists; still verify against current code and tests.
- **In progress:** work has started but acceptance criteria are incomplete.
- **Planned:** no claim of implementation.
- **Release gate:** must pass before declaring the migration/release complete.

---

## Milestone 0 — Repository baseline and reproducible development

**Priority:** P0 · **Prerequisite:** none · **Exit condition:** contributors can build and run the same baseline without destructive Git cleanup.

- [ ] Record a reproducible baseline for `cargo fmt --all -- --check`, `cargo check --workspace`, `cargo test --workspace`, Flutter analysis/tests/builds and any existing .NET build.
- [ ] Resolve the known Rust formatting failure in `core/src/lib.rs` in a focused change; do not suppress formatting or bundle unrelated edits.
- [ ] Review existing GitHub Actions status and branch protection; distinguish historical successful runs from current branch checks.
- [ ] Add a developer setup page for Rust, Flutter stable/Dart, Windows Visual Studio C++ desktop workload, and macOS Xcode.
- [ ] Document exact native artifact names, target triples, build modes and expected output paths from Cargo configuration.
- [ ] Add a script or documented commands for building the Rust shared library independently from either frontend.
- [ ] Ensure local Flutter-generated `windows/` and `macos/` runner files are understood, reviewed and intentionally tracked/ignored; do not discard user-generated files blindly.
- [ ] Establish a non-destructive Git workflow: inspect `git status -sb`, current branch and merge state before switching, pulling or resolving conflicts.
- [ ] Set a consistent policy for warnings: fix new warnings; do not convert warnings into errors without reviewing legacy baseline.
- [ ] Define supported OS versions and minimum hardware assumptions.

**Acceptance:** a clean checkout can follow the documented build/test steps; CI failures are visible and attributable; no unverified baseline claim is called “green”.

## Milestone 1 — Flutter desktop foundation and UX reliability

**Priority:** P0 · **Depends on:** Milestone 0 · **Status:** visual prototype exists; mock-only.

- [x] Establish isolated Flutter workspace, theme tokens, arrangement layout, browser, device/instrument dock and demo mixer.
- [x] Use compact DAW/IDE-style menus and transport instead of oversized product branding.
- [ ] Promote `prototypes/aetherband-flutter-ui/` into the official app path only after the native adapter and run/build paths are ready; preserve Git history and avoid premature folder churn.
- [ ] Define app navigation and pane model: arrangement, browser, inspector/device chain, mixer, piano roll (future), settings and diagnostics.
- [ ] Add stable IDs and production domain models for sessions, tracks, regions/clips, devices, effects, automation and assets; keep mock/demo models separate.
- [ ] Add a typed application state layer and explicit commands/events rather than scattered widget-local production state.
- [ ] Define one authoritative state source for engine telemetry and one for editable project state.
- [ ] Add responsive layout tests at realistic desktop sizes, small window sizes, high-DPI scaling and resize transitions.
- [ ] Fix/guard every RenderFlex overflow and ensure timeline, mixer and sidebars remain usable at different window sizes.
- [ ] Add keyboard navigation, focus indicators, semantic labels, accessible hit targets and screen-reader descriptions where appropriate.
- [ ] Implement global shortcuts with configurable bindings and conflict detection; ensure text fields and native menus behave correctly.
- [ ] Add command palette / action search for discoverability, inspired by music workstations and IDEs without copying proprietary assets.
- [ ] Add application menus with accurate enabled/disabled states and consistent shortcuts.
- [ ] Implement persistent pane visibility, width/height, zoom and layout preferences.
- [ ] Add settings for audio device, sample rate/buffer size where supported, UI scaling, theme accents and keyboard shortcuts.
- [ ] Add a non-mock “engine disconnected / no device / load failed” UI state.
- [ ] Add screenshot or golden tests for key layout regions and design tokens.
- [ ] Keep the established dark charcoal, warm-paper, sage, magenta and blue accent language consistent.
- [ ] Provide empty states, progress states, cancellation and actionable errors for expensive operations.

**Acceptance:** UI is stable and responsive, interactions are testable, no control implies unsupported real functionality, and CI validates Windows and macOS builds.

## Milestone 2 — C ABI audit, Dart FFI and native library loading

**Priority:** P0 · **Depends on:** Milestones 0–1 · **Status:** Dart adapter not yet implemented at last handoff.

- [ ] Treat `bindings/c_abi/src/lib.rs` as source of truth; verify every exported symbol and `#[repr(C)]` layout before binding.
- [ ] Add/validate a canonical C header for the public ABI, including opaque handles, structs, function signatures, ownership, nullability, return codes and threading rules.
- [ ] Add ABI version/compatibility checks and a test that detects accidental symbol or layout drift.
- [ ] Implement a small Dart `dart:ffi` adapter and an injectable `EngineController`/repository interface for Flutter.
- [ ] Decide whether to use generated Dart bindings or reviewed handwritten bindings after evaluating supported tooling; do not assume `csbindgen` emits Dart.
- [ ] Bind engine create/destroy, API version, play/pause/stop, master volume, device enumeration/selection, track load/remove/control and telemetry that actually exist.
- [ ] Mirror C ABI layouts byte-for-byte, including alignment, integer widths, booleans, fixed-size strings and arrays; test layout assumptions on both platforms.
- [ ] Serialize calls for each engine handle through one owner/control boundary until native concurrency guarantees are explicitly designed and tested.
- [ ] Ensure engine destruction waits for in-flight calls and polling stops before native resources are freed.
- [ ] Check every native return code; map errors to typed Dart results and user-visible diagnostics.
- [ ] Load the correct Windows DLL / macOS dynamic library from predictable development and packaged locations.
- [ ] Add diagnostics for missing library, incompatible ABI version, engine creation failure, missing audio device and device-open errors.
- [ ] Test repeated create/destroy, repeated device queries, repeated track load/remove, invalid handles/indices, and shutdown while telemetry is being polled.
- [ ] Add FFI integration tests that use a built native library, separate from pure widget tests.
- [ ] Ensure the UI never calls FFI on every paint/build and never busy-polls telemetry.
- [ ] Establish bounded telemetry polling or a safe event bridge, with cancellation on app pause/close.
- [ ] Keep a fake engine only as an injected test double; production startup must choose the real adapter or show a clear error.
- [ ] Document ABI evolution rules and how changes must be synchronized across Rust, the C header, Dart and the temporary C# consumer.

**Acceptance:** real Dart code can load the native library, validate ABI version, create/destroy an engine, return meaningful errors and query telemetry on Windows and macOS without races or leaks.

## Milestone 3 — Real-engine Flutter parity (minimum useful DAW)

**Priority:** P0 · **Depends on:** Milestone 2.

- [ ] Initialize the real engine on application startup and dispose it deterministically on shutdown.
- [ ] Enumerate audio devices and allow the user to select a device; reflect failures and selected device state truthfully.
- [ ] Surface native audio/device errors with recovery actions and useful diagnostics.
- [ ] Import supported audio files through a file picker and load them using existing ABI functions.
- [ ] Track actual native track IDs and map them to stable UI track models; never assume list index equals native identity unless contract guarantees it.
- [ ] Show loading/progress/error states and allow cancellation where the engine supports cancellation.
- [ ] Connect play, pause and stop to native operations and authoritative telemetry.
- [ ] Verify Stop silences output, resets playhead and restarts decoders as intended; do not reopen the previously fixed issue without current failing evidence.
- [ ] Connect per-track volume, pan and mute to real engine functions.
- [ ] Connect master volume to the native engine.
- [ ] Show real playhead, duration, playing state and peak/RMS meters from native telemetry.
- [ ] Handle empty sessions, missing files, unsupported formats, corrupt files, device disconnect, engine crash and library-load failure.
- [ ] Ensure removing tracks updates both native engine and UI state consistently.
- [ ] Add integration tests for play/pause/stop, track lifecycle, volume/pan/mute, telemetry and repeated use.
- [ ] Run manual audio tests on Windows WASAPI and macOS CoreAudio with actual devices; record OS, device, sample rate and test result.
- [ ] Verify the no-allocation real-time test remains green after any engine/API changes.
- [ ] Clearly label decoder format status: WAV has been tested; other advertised formats need end-to-end verification.
- [ ] Remove fake transport and fake meter paths from production mode once native parity exists.
- [ ] Add a diagnostics panel with engine version, ABI version, selected device, sample rate, buffer/latency information when available and last native error.

**Acceptance:** every feature the existing Avalonia app currently supports with real audio has an equivalent real Flutter workflow, backed by integration and manual platform evidence.

## Milestone 4 — Session/project model, file safety and persistence

**Priority:** P1 · **Depends on:** Milestone 3; model design can start earlier.

- [ ] Define a versioned project/session schema for tempo, meter, tracks, clips/regions, source assets, routing, gain/pan/mute/solo, markers and UI state.
- [ ] Decide whether to use an established interchange format such as DAWproject where practical; document compatibility goals and limitations before committing to a format.
- [ ] Implement save, Save As, Open, Recent Projects, New Project and close-with-unsaved-changes flows.
- [ ] Add autosave and crash-recovery snapshots with bounded disk work away from the audio thread.
- [ ] Make project loading atomic: failed loads must not leave a half-mutated engine/session.
- [ ] Resolve assets via relative paths and a project media directory; report missing media and offer relink.
- [ ] Add optional “collect/copy media into project” behavior for portable sessions.
- [ ] Store schema version and implement migrations for older projects.
- [ ] Write project files atomically (temporary file + safe replace) and protect against corruption.
- [ ] Add undo/redo command history for project edits with a documented scope.
- [ ] Separate engine runtime IDs from persistent project IDs.
- [ ] Test save/reopen round-trips, missing assets, invalid project files, interrupted writes, migration and large sessions.
- [ ] Add a project browser with create/open/recent/rename/reveal-in-file-manager operations.
- [ ] Define backup/restore behavior and ensure no silent overwrite of user projects.

**Acceptance:** users can safely save, close, reopen and move a project with its media; corrupt or missing data produces a recoverable error.

## Milestone 5 — Timeline and editing workflow

**Priority:** P1 · **Depends on:** Milestones 3–4.

- [ ] Implement accurate timeline coordinate mapping for bars/beats, seconds and samples; define zoom/pan math and test rounding.
- [ ] Add clip/region selection, multi-selection, drag, trim, move, duplicate, split, delete and edge snapping.
- [ ] Add snap-to-grid, snap-to-transient (after transient detection), grid resolution and snap enable/disable.
- [ ] Add loop range, cycle playback, range selection and punch markers.
- [ ] Add playhead scrubbing with safe seek behavior and clear limitations if seeking is not yet supported by the engine.
- [ ] Add track creation, rename, reorder, duplicate and delete with confirmation when destructive.
- [ ] Add mute, solo, record-arm and input monitoring states only when engine behavior exists.
- [ ] Add track types and visual semantics: audio, MIDI/instrument, bus/aux, master and automation.
- [ ] Add markers, regions, color labels and section navigation.
- [ ] Add waveform peak cache generation and drawing from actual file data; keep heavy analysis off the UI isolate.
- [ ] Add peak cache invalidation for changed/relinked media and scalable rendering for long recordings.
- [ ] Add clip fade-in/fade-out and crossfades with click-free audio behavior.
- [ ] Add keyboard editing, tool modes, context menus and precise numeric entry.
- [ ] Add large-session virtualization/culling so only visible clips/lanes are rendered.
- [ ] Add timeline stress tests with hundreds of tracks and thousands of regions.
- [ ] Add accessibility/keyboard alternatives to mouse-only drag operations.
- [ ] Define sample-accurate editing semantics and tests for frame/beat conversion.

**Acceptance:** common arrange/edit tasks can be performed accurately, undoable where appropriate, and remain responsive on large projects.

## Milestone 6 — Recording and audio asset pipeline

**Priority:** P1 · **Depends on:** Milestones 2–5.

- [ ] Extend native device abstraction to support input capture where `cpal` and platform permissions allow.
- [ ] Add explicit input device/channel enumeration and input/output routing models.
- [ ] Implement record-arm, record start/stop, pre-roll, punch-in/out and input monitoring.
- [ ] Write captured audio to disk through a dedicated non-real-time writer; never write files in the audio callback.
- [ ] Define recording buffer capacity, overrun detection, disk-full handling and recovery of incomplete recordings.
- [ ] Add input latency compensation and record-offset calibration where possible.
- [ ] Add permission flows and device-loss behavior on Windows/macOS.
- [ ] Generate waveform peaks and duration metadata in background workers after recording/import.
- [ ] Add peak cache format/versioning and a policy for regenerating caches.
- [ ] Add import options for mono/stereo, sample-rate conversion, channel mapping and supported format warnings.
- [ ] Verify WAV and then separately test FLAC, MP3, OGG and AAC/M4A end-to-end, including metadata, seek, channel layout and error paths.
- [ ] Add disk-space warnings, large-file tests and safe handling of interrupted recordings.

**Acceptance:** record and import real audio with bounded real-time behavior, reliable files, correct waveforms and documented format support.

## Milestone 7 — MIDI, timing and instruments

**Priority:** P2 · **Depends on:** session model and engine timing design.

- [ ] Define a sample-accurate musical clock with tempo map, time signatures, bars/beats/ticks and transport position.
- [ ] Implement MIDI event types, routing and timestamping without sending high-rate event work through the Flutter UI.
- [ ] Add MIDI input device discovery, connection, disconnection and permission/error handling.
- [ ] Add MIDI recording, quantization, note editing, velocity, controller lanes and event cleanup.
- [ ] Build a piano roll with note creation, selection, resize, move, velocity editing, snap/grid and zoom.
- [ ] Add keyboard input support and latency/monitoring behavior.
- [ ] Define an instrument plugin/API architecture before committing to built-in synth implementation details.
- [ ] Implement first-party synths as native DSP components, with presets and parameter automation.
- [ ] Consider sampler, oscillator/subtractive synth, wavetable or granular instruments in deliberate stages rather than all at once.
- [ ] Add a preset browser with tagging, search, favorites, versioned preset format and safe parameter restoration.
- [ ] Add MIDI file import/export and tests for tempo maps, overlapping notes, sustain and malformed files.

**Acceptance:** MIDI timing is deterministic, piano-roll editing is usable, and instruments generate audio through the native engine.

## Milestone 8 — Mixer, routing, effects and plugin ecosystem

**Priority:** P2 · **Depends on:** stable engine graph, project format and plugin decisions.

- [ ] Design an explicit audio graph with track, bus/aux, send, return, master and sidechain semantics.
- [ ] Implement routing changes safely without reallocating or locking in the audio callback; define graph-swap strategy.
- [ ] Add pre/post-fader sends, bus routing, channel count handling and feedback-loop prevention.
- [ ] Add native effect chain infrastructure with bypass, order, wet/dry, latency reporting and preset/state serialization.
- [ ] Build first-party effects: gain, pan, EQ, compressor, gate, delay, reverb, chorus, saturation and limiter, each with DSP tests.
- [ ] Add peak/RMS/LUFS metering where appropriate, clip indicators, reset/hold behavior and clear metering semantics.
- [ ] Decide plugin formats and legal/technical scope deliberately: VST3, CLAP and AU support have different platform/licensing constraints; do not promise all formats before validating them.
- [ ] Implement plugin discovery, scanning in a separate process if needed, crash isolation, blacklist and scan cache.
- [ ] Handle plugin UI lifecycle, parameters, preset/state save/restore, automation and missing-plugin placeholders.
- [ ] Add plugin sandbox/recovery strategy and prevent a plugin crash from corrupting project state where feasible.
- [ ] Add offline/plugin compatibility test suite and plugin scan diagnostics.
- [ ] Add latency compensation for plugin and routing paths.
- [ ] Ensure plugin DSP cannot violate audio-thread deadlines without containment/mitigation.

**Acceptance:** routing/effects work on real audio, project reopen restores state, plugin failures are recoverable, and real-time constraints are measurable.

## Milestone 9 — Automation, modulation and advanced arrangement

**Priority:** P2 · **Depends on:** stable parameter and project models.

- [ ] Add automation lanes for volume, pan, sends, effect parameters and instrument parameters.
- [ ] Define interpolation types, sample/beat coordinate rules, smoothing and automation write/read modes.
- [ ] Add touch/latch/write modes only with clear semantics and tests.
- [ ] Add modulation sources and destinations with bounded native processing.
- [ ] Add tempo and time-signature changes, tempo-following clips and time-stretch/pitch-shift policy.
- [ ] Add markers, arrangement sections, region groups and navigation shortcuts.
- [ ] Add comping/take lanes, playlists and non-destructive editing if they fit the product scope.
- [ ] Add transient detection, quantization, time stretching and pitch shifting after selecting/testing appropriate algorithms.
- [ ] Add spectral/advanced editing only after performance and UX research.
- [ ] Add automation stress tests and deterministic render tests.

**Acceptance:** automation and timing changes are sample-accurate enough for the documented product goals and persist correctly across project reopen.

## Milestone 10 — Export, rendering and delivery

**Priority:** P1 for a usable DAW; implementation can begin after stable mix graph.

- [ ] Implement offline rendering independent of real-time hardware output.
- [ ] Define render settings: sample rate, bit depth, channel layout, normalization, dither and tail handling.
- [ ] Add export to WAV first; evaluate compressed formats separately and document encoder/licensing constraints.
- [ ] Support time selection, whole project, stems, individual tracks and buses where routing permits.
- [ ] Add progress, cancellation, estimated output size, disk-space checks and safe overwrite confirmation.
- [ ] Ensure offline render uses the same DSP/routing graph semantics as real-time playback.
- [ ] Add deterministic render regression fixtures and compare outputs within documented tolerances.
- [ ] Add export metadata and naming templates.
- [ ] Test silent projects, clipping, long durations, effect tails, missing plugins and invalid export destinations.

**Acceptance:** a user can render a project or selected range to a documented format and receive a valid file with expected duration/channels and recoverable failures.

## Milestone 11 — Reliability, performance and professional polish

**Priority:** P1 · **Runs throughout; release gate before 1.0.

- [ ] Establish audio latency, callback deadline, underrun/dropout and CPU usage benchmarks on supported platforms.
- [ ] Add diagnostics for xruns/underruns, device errors, decoder starvation, clipping and plugin latency where applicable.
- [ ] Run soak tests: long playback, many tracks, repeated project open/close, device changes, suspend/resume and app shutdown.
- [ ] Add property/fuzz tests for project parsing, ABI inputs, decoder errors and malformed media where appropriate.
- [ ] Add crash recovery, autosave, log rotation and a user-controlled diagnostics export that avoids leaking project/media contents.
- [ ] Add memory/performance budgets for timeline drawing, waveform caches, plugin scanning and large projects.
- [ ] Verify high-DPI, multiple monitors, window restore, OS theme, keyboard layout and platform-specific file dialogs.
- [ ] Add accessibility checks, localization groundwork and readable contrast for all meter/clip colors.
- [ ] Add privacy/security review for file paths, diagnostics and plugin scanning.
- [ ] Document supported audio formats, plugin formats, known limitations and troubleshooting.
- [ ] Maintain a regression suite for transport, track removal, Stop/restart, device changes and engine lifecycle.
- [ ] Add dependency/license audits and software supply-chain checks to CI.
- [ ] Ensure application updates and project format migrations are safe and documented.

**Acceptance:** no known release-blocking data-loss or audio-thread-safety issue; performance claims are backed by measurements, not assumptions.

## Milestone 12 — Packaging, installation and release

**Priority:** P1 · **Depends on:** Flutter default-app gate and core workflows.

- [ ] Make Flutter the documented default build/run path for Windows and macOS.
- [ ] Create signed/notarized macOS artifacts as needed and Windows installer/package artifacts.
- [ ] Bundle the correct Rust dynamic library for each target architecture and verify runtime loading from the installed app.
- [ ] Set final app name, icons, versioning, copyright/license notices and file associations.
- [ ] Define release channels, changelog format, versioning and rollback procedure.
- [ ] Add CI artifact retention and reproducible release builds where feasible.
- [ ] Test install, upgrade, uninstall, user-data preservation and clean-machine startup.
- [ ] Add crash/error reports that are opt-in or otherwise privacy-conscious and document their behavior.
- [ ] Publish checksums, release notes, supported OS versions and known issues.
- [ ] Create a clean-user smoke-test checklist that does not rely on a developer's PATH or generated files.
- [ ] Ensure project files remain usable after application upgrades.

**Acceptance:** a new user can install and launch Aetherband without manually assembling the developer toolchain, load audio, use supported features and preserve projects across upgrades.

## Milestone 13 — Flutter parity sign-off and C# / Avalonia retirement

**Priority:** P0 release gate for final architecture · **Depends on:** Milestones 2, 3, 11 and 12.

C# / Avalonia is **likely to be removed from the final product/repository** after migration. This is expected, not an immediate action. Do not start deletion merely because the Flutter mock looks correct.

- [ ] Create a feature-by-feature parity matrix from the actual existing Avalonia app and engine-supported operations.
- [ ] Demonstrate every existing audio-connected workflow in Flutter using the real engine.
- [ ] Verify Windows and macOS runtime audio on representative devices, including error/recovery paths.
- [ ] Ensure default CI builds/tests Flutter and the native engine; no required workflow depends on Avalonia.
- [ ] Move build scripts, setup docs, screenshots, issue templates and release paths to Flutter.
- [ ] Ensure ABI and native integration tests are independent of the legacy C# client.
- [ ] Obtain explicit owner review of the parity matrix and migration evidence.
- [ ] In a separate PR, remove the Avalonia project and C#-only binding generation/dependencies/workflows after review.
- [ ] Keep `core/`, `bindings/c_abi/`, public C header, Dart FFI bindings and native ABI tests intact.
- [ ] Search for obsolete project names/namespaces (including historical `RouletteStudio`) and rename only where safe and independently reviewable.
- [ ] Remove obsolete docs/scripts only after confirming no supported workflow still depends on them.

**Acceptance:** Flutter is the only maintained shipped desktop UI, real audio parity is proven, and the Rust engine/C ABI remains fully supported.

## Cross-cutting test matrix

| Area | Automated evidence | Manual/platform evidence |
|---|---|---|
| Rust engine | format, check, unit/integration tests, real-time allocation tests | device startup, transport, long playback, stop/restart |
| C ABI | symbol/layout/version tests, error/ownership tests | library loading and ABI version on Windows/macOS |
| Dart FFI | binding/layout tests, fake adapter tests, integration tests | installed native library, device errors, app shutdown |
| Flutter UI | analyze, widget tests, golden/layout tests, accessibility checks | resizing, high-DPI, keyboard navigation, multi-monitor |
| Audio workflow | integration tests for track/transport/mix controls | audible playback, device changes, real file imports |
| Projects | schema/migration/round-trip/fuzz tests | recovery after interrupted save and missing media |
| Recording/export | file validity, duration/channel/render regression tests | record/playback, disk-full, cancel and recovery |
| Release | artifact/signing/installer smoke tests | clean machine install, upgrade, uninstall and project retention |

## Suggested implementation order for the next coding sessions

1. Fix and record the Rust formatting baseline in a focused change.
2. Audit and test the actual C ABI, create/validate the canonical header and define ownership/thread rules.
3. Implement the Dart FFI adapter and native library loading with integration tests.
4. Replace mock transport, telemetry, device selection, track loading/removal, volume/pan/mute with real engine calls.
5. Prove Flutter feature parity with the existing Avalonia app on Windows and macOS.
6. Implement project/session persistence and real waveform generation.
7. Add timeline editing, recording and export.
8. Add MIDI/instruments, routing/effects/plugins, automation and advanced production workflows in dependency order.
9. Package and release Flutter as the default desktop app.
10. Retire C#/Avalonia only after explicit owner-approved parity sign-off.

The detailed current ABI inventory and FFI safeguards live in [FLUTTER_DESKTOP_MIGRATION.md](FLUTTER_DESKTOP_MIGRATION.md); use it as the implementation contract and this file as the broader product backlog.

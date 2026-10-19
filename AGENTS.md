# Aetherband — Mandatory Agent and Contributor Instructions

Read this file before changing code or documentation. The repository is migrating toward a native C++/JUCE desktop DAW; legacy implementation details must not override this decision.

## Product and committed stack

- Primary language: C++20 or newer.
- Desktop framework: JUCE — committed decision, not a candidate.
- Build: CMake.
- Required platforms: Windows and macOS.
- Audio engine: Aetherband-owned runtime and DSP semantics, using JUCE for native application/audio/platform infrastructure.
- License goal: GPL-3.0-or-later with compatible dependencies.
- Legacy reference only: Rust engine, C ABI, Flutter, and Dart. Preserve them during migration for behavior comparisons; do not use them for new product features.
- C# is not part of the planned core. Another language requires an explicitly approved, concrete need.

## Read before substantial work

1. docs/ARCHITECTURE.md
2. docs/PROJECT_STATE.md
3. docs/CPP_MIGRATION_PLAN.md
4. docs/FEATURE_TRACKER.md
5. docs/DECISIONS.md
6. docs/AI_WORKFLOW.md
7. native/README.md for native-target work
8. docs/AUDIO_ENGINE.md for real-time constraints and docs/PROJECT_FORMAT.md for session persistence

## Non-negotiable rules

- Do not delete the Rust/Flutter/Dart implementation wholesale. Preserve it until the C++/JUCE replacement passes explicit acceptance criteria; retain Git history afterward.
- New product features belong in C++/JUCE unless an approved task explicitly concerns legacy maintenance.
- Port observed behavior and tests, not source mechanically. Audit old code before treating its documentation as truth.
- Do not claim code builds, tests pass, or devices work unless checks were actually run.
- A DSP graph must process samples; metadata and ordering alone are not an executing engine.
- The audio callback must not perform I/O, unpredictable allocation/deallocation, blocking calls, or wait on contended locks.
- Prepare resources and complex processor changes away from the callback; document ownership, thread safety, and teardown.
- Keep UI, session model, media, runtime, DSP, and instruments independently testable.
- JUCE is committed; do not replace it with Flutter, Tauri, or another UI stack without an explicit owner decision.
- Verify JUCE version, modules, platform requirements, and licence/distribution obligations before release.
- Treat Windows and macOS as required; platform support must be demonstrated separately.
- Do not assume formats other than WAV are supported based on legacy reports.

## Required workflow

1. Inspect the branch, source, build files, tests, and CI.
2. Identify target C++/JUCE work versus narrowly scoped legacy maintenance.
3. Make a coherent change and add tests.
4. Build and run available checks; if unavailable, say so.
5. Update project state, feature tracking, and decisions when architecture or verification changes.
6. Report files changed, checks run, outcomes, platform coverage, and limitations.

A compile is not proof of working audio. Source presence is not proof of a complete feature.

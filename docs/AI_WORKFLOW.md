# AI-Assisted Development Workflow — Aetherband

> Start with AGENTS.md. The binding architecture is C++/JUCE, CMake, Windows and macOS. This file defines task and verification expectations for human contributors and AI coding agents.

## Authority and responsibility

The project owner decides product direction and architecture. Agents may research, design, implement, test, and recommend changes, but must not silently change committed decisions. JUCE is the committed framework; Flutter/Tauri or another replacement requires explicit owner approval.

## Before changing code

1. Inspect branch, working tree, source, build files, tests, and CI.
2. Read ARCHITECTURE.md, PROJECT_STATE.md, and FEATURE_TRACKER.md.
3. Identify target C++/JUCE work versus explicitly scoped legacy maintenance.
4. Check existing behavior before porting. Documentation and API declarations are not runtime evidence.
5. Check dependency licensing and platform support before introducing libraries.

## Implementation rules

- Prefer small, coherent, reviewable changes with tests.
- Keep UI, session model, media, runtime, DSP, and instruments separated.
- Protect real-time callback safety: no blocking I/O, unpredictable allocation, or contended waits.
- Keep complex preparation and destruction off the audio callback.
- Port behavior rather than source mechanically.
- Preserve the legacy Rust/Flutter/Dart implementation until target acceptance criteria pass.
- Update architecture decisions when the owner changes direction; do not silently reverse ADR-008.
- Update project state and feature tracker when implementation or verification changes.

## Verification and handoff

Run relevant builds and tests where available. Report exact commands and outcomes; operating system and compiler/toolchain; unit, integration, offline audio, and manual device tests separately; known limitations and untested paths; dependency/licensing changes; and documentation updated.

Never claim Windows/macOS support without platform evidence. A compile is not proof of audio playback; a passing offline test is not proof of device lifecycle; a visual prototype is not a complete DAW. If a check could not be run, say so and provide the exact next command or test needed.

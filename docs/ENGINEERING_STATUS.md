# Aetherband — Historical Engineering Status Snapshot

> **Historical record, not current implementation guidance.** This snapshot concerns earlier architecture and repository state. The current binding direction is native C++/JUCE as recorded in ADR-008 in DECISIONS.md. Use README.md, ARCHITECTURE.md, PROJECT_STATE.md, FEATURE_TRACKER.md, and CPP_MIGRATION_PLAN.md for current target direction.

This file is retained to preserve context about earlier stabilization work. Branch names, PR states, test reports, framework references, and risk assessments in the original snapshot may be stale. Verify current source, CI, and GitHub state before acting on any historical detail.

## How to interpret this document

- Statements about Rust, C ABI, Flutter, Dart, C#, Avalonia, or earlier PRs describe historical implementations.
- Legacy code may help explain behavior but does not establish C++/JUCE parity.
- Current C++ code presence does not prove compilation or runtime correctness.
- Windows and macOS support requires platform-specific evidence.
- Audio-device playback requires real device testing; offline tests alone are insufficient.

## Current migration target

C++20 or newer, JUCE, CMake, Windows and macOS. Aetherband owns its DSP graph semantics, processor lifecycle, routing, transport, and offline-rendering rules. See the current docs listed above.

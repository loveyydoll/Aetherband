# Aetherband — Agent Entry Point

This is the mandatory entry point for AI coding agents and contributors. Read it before making changes.

## Product and target stack

Aetherband is an early-stage, open-source desktop DAW. Its direction is an expressive arrangement-first workspace with native audio processing and an Aetherband-owned DSP architecture.

- **Target language:** C++20 or newer where supported.
- **Build system:** CMake.
- **Desktop framework:** not finalized; JUCE is a leading candidate, not yet an unconditional requirement.
- **Platforms:** Windows and macOS are required targets.
- **DSP:** build a real executing graph with explicit processor, routing, parameter and lifecycle contracts.
- **Optional C#:** only add it for a specific justified use case behind a clear boundary.
- **Legacy reference:** Rust engine, C ABI, Flutter and Dart are being phased out of the target architecture but must remain available during migration for behavioral comparison.

Verify current source, build files, tests and CI before claiming anything works. Documentation is a guide, not runtime evidence.

## Read before editing

1. [C++ migration plan](docs/CPP_MIGRATION_PLAN.md) — migration sequence and acceptance criteria.
2. [Project state](docs/PROJECT_STATE.md) — current target architecture and uncertainties.
3. [Feature tracker](docs/FEATURE_TRACKER.md) — feature status and evidence.
4. [AI workflow](docs/AI_WORKFLOW.md) — task lifecycle, verification and handoff.
5. [Architecture](docs/ARCHITECTURE.md), [audio engine notes](docs/AUDIO_ENGINE.md), [project format](docs/PROJECT_FORMAT.md), and [decisions](docs/DECISIONS.md) as relevant.
6. [Native foundation README](native/README.md) and `native/CMakeLists.txt` for the current C++ entry point.

## Non-negotiable engineering rules

- Do not delete the Rust/Flutter/Dart implementation wholesale. Preserve it as a reference until the C++ replacement passes explicit acceptance criteria.
- Port behavior and tests, not Rust source mechanically.
- Never claim Windows/macOS runtime or audio hardware support without testing those platforms.
- Never label a feature complete because an API or data structure exists.
- A graph that only stores node metadata is not an executing DSP graph.
- Do not allocate, perform I/O, or block on a contended lock in the real-time audio callback.
- Prepare processors and buffers away from the callback; document ownership and teardown.
- Keep UI, project state, media, audio runtime, DSP and instruments separated by clear contracts.
- Keep third-party dependencies license-compatible with GPL-3.0-or-later and document trade-offs.
- Distinguish implemented, automated-tested, manually verified, prototype and planned work.

## Required workflow

1. Inspect the current branch and working tree before changes.
2. Identify whether the task targets the C++ foundation or maintenance of legacy code.
3. Make the smallest coherent change and add tests.
4. Build and run relevant tests where tools are available.
5. Report exactly what was tested, on which platform, and what remains unverified.
6. Update project state, feature tracking and architecture docs when the direction or verified status changes.

## Definition of done

A change is not done merely because code was written. It should compile, have relevant tests, preserve documented contracts, report failures honestly, and state any platform or runtime verification that could not be performed.

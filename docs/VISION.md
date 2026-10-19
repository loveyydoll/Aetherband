# Product Vision: Aetherband

Aetherband is a free and open-source desktop DAW for following musical ideas wherever they lead. It should bring recording, arrangement, editing, mixing, synthesis, and sound design into one expressive environment.

The creative direction values immediacy and precision without imitating any single existing DAW. The workspace should feel designed for music: clear arrangement and mixer workflows, purposeful visual hierarchy, fast keyboard/mouse interaction, and room for unusual textures, layered productions, and artist-specific instruments.

This is a target vision, not a claim that the current prototype already provides these workflows.

## Committed architecture

- C++20 or newer as the primary language.
- JUCE as the native application, UI, audio, and platform framework.
- CMake as the build system.
- Windows and macOS as required desktop targets.
- Aetherband-owned DSP graph semantics, processor lifecycle, routing, transport, parameter/automation behavior, and offline-rendering rules.
- GPL-3.0-or-later as the license goal, with compatible dependency choices.

Rust, C ABI/Dart FFI, Flutter, and Dart are legacy references only. Do not build new target features on that stack. C# is not planned for the core.

## Principles

1. Creative continuity: recording, arrangement, editing, mixing, and sound design should work together.
2. Native reliability: device lifecycle, timing, recovery, shutdown, and media handling must be tested.
3. DSP ownership: Aetherband owns graph execution semantics without reinventing every established algorithm.
4. Real-time discipline: no blocking I/O, unpredictable allocation, or contended waits in the audio callback.
5. Modularity: UI, session model, media, runtime, DSP, and instruments have clear contracts.
6. Open development: architecture, trade-offs, limitations, and dependency licensing remain inspectable.
7. Honest progress: distinguish planned work, implementation, automated tests, and platform/device verification.

## First product milestone

Build a native JUCE application on both Windows and macOS, open/close an audio device, and play a known signal safely. Then prove a minimal DAW workflow: import WAV, arrange multiple tracks, play/mix, save/reopen, and export WAV.

See ARCHITECTURE.md, CPP_MIGRATION_PLAN.md, and ROADMAP.md.

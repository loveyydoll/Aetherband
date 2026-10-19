---
applyTo: "**/*.cpp, **/*.cc, **/*.cxx, **/*.hpp, **/*.h, **/CMakeLists.txt"
---

# C++/JUCE Engineering — Aetherband

- Read AGENTS.md, docs/ARCHITECTURE.md, docs/CPP_MIGRATION_PLAN.md, and docs/PROJECT_STATE.md before substantial changes.
- Use C++20 or newer unless a verified platform/compiler constraint requires otherwise.
- JUCE is the committed native framework. Do not replace it with Flutter, Tauri, or another framework without an explicit owner decision.
- Keep code buildable on Windows and macOS; validate both independently.
- Separate UI, session model, media, runtime, DSP, and instruments behind clear contracts.
- The audio callback must not perform I/O, unpredictable allocation/deallocation, blocking calls, or wait on contended locks.
- Prepare buffers/processors away from the callback; define safe handoff, ownership, replacement, and teardown.
- Do not assume JUCE abstractions automatically make code real-time safe.
- Add deterministic buffer/DSP/offline-audio tests and integration/device tests for lifecycle behavior.
- Validate buffer dimensions, channel layouts, parameter ranges, graph connections, and failure paths.
- Do not claim a graph works unless it processes samples.
- Prefer RAII and explicit ownership; avoid hidden mutable global state.
- Review JUCE version, modules, licence/distribution obligations, and all third-party dependencies.
- Report exact commands, tests, outcomes, OSes, and device coverage; state what was not tested.

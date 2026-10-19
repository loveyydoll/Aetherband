---
applyTo: "**/*.cpp, **/*.cc, **/*.cxx, **/*.hpp, **/*.h, **/CMakeLists.txt"
---

# C++ Engineering — Aetherband

- Read `AGENTS.md`, `docs/CPP_MIGRATION_PLAN.md`, `docs/ARCHITECTURE.md`, and `docs/PROJECT_STATE.md` before substantial changes.
- Target C++20 unless a verified compiler/platform constraint requires otherwise.
- Keep code buildable on Windows and macOS; do not silently add platform-specific assumptions to shared code.
- Keep UI, session model, media, audio runtime, DSP and instruments in distinct modules with documented interfaces.
- Treat real-time callback safety as a hard constraint: no file/network I/O, unpredictable allocation, blocking calls, or contended locks in the callback.
- Prepare processors and buffers off the audio thread and define safe ownership, replacement and teardown.
- Add deterministic unit tests for DSP and audio-buffer behavior; use offline render tests before hardware-only validation.
- Validate buffer dimensions, channel layouts, parameter ranges and failure paths explicitly.
- Do not claim a graph is functional until it actually processes audio.
- Prefer clear ownership and RAII; avoid hidden global mutable state.
- Keep third-party dependencies compatible with GPL-3.0-or-later and record significant license or architecture decisions.
- Report the exact builds/tests run and clearly state if Windows/macOS or hardware testing was unavailable.

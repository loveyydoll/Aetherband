# Legacy Engine Foundation Audit — Migration Reference

**Status:** Historical/source-review artifact. This audit describes the legacy Rust/Flutter architecture and is not a recommendation to keep it as the target. The current decision is C++/JUCE under ADR-008 in DECISIONS.md.

## Why retain this audit?

The previous implementation contains behavior and design decisions that may be useful when migrating transport, decoding, mixing, session persistence, and UI workflows. It must be treated as a source of hypotheses to verify—not proof of correctness, production readiness, or platform support.

## How to use it

- Re-inspect current source and tests before porting any subsystem.
- Record whether each behavior is observed in code, covered by automated tests, verified offline, or manually tested with hardware.
- Port behavior and requirements, not Rust types or dependencies mechanically.
- Translate real-time safety requirements into C++ contracts and test the actual callback path.
- Keep the old implementation available until the replacement passes corresponding acceptance criteria.

## Current migration target

C++20+ / JUCE / CMake; Windows and macOS required. Aetherband owns DSP graph semantics, processor lifecycle, routing, transport, and offline rendering. See ARCHITECTURE.md, CPP_MIGRATION_PLAN.md, and FEATURE_TRACKER.md.

## Evidence cautions

The existence of CPAL output, decoding/resampling modules, a mixer, graph metadata, or a C ABI does not prove end-to-end reliability. Previous reports identified WAV as the only format tested. Hardware playback and platform coverage must be re-established for the C++ target.

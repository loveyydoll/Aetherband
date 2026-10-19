# Legacy Flutter Desktop Reference

**Status: retired target architecture; retained for migration and behavior comparison only.**

The desktop app in this directory was built with Flutter/Dart and communicated with the legacy Rust audio engine through a C ABI and Dart FFI. This is not the target architecture. The committed direction is a native C++/JUCE application under ADR-008 in docs/DECISIONS.md.

## When to use this directory

Use it only to inspect historical UI behavior, session workflows, FFI contracts, or regression expectations while migrating to C++/JUCE. Do not add new product features here unless the project owner explicitly requests legacy maintenance.

## Preservation policy

Do not delete this code wholesale. Keep it available until the corresponding C++/JUCE behavior passes documented acceptance criteria. Do not assume a working Flutter screen proves physical audio behavior or native parity.

## Target migration references

- docs/ARCHITECTURE.md
- docs/CPP_MIGRATION_PLAN.md
- docs/PROJECT_STATE.md
- docs/FEATURE_TRACKER.md
- docs/UI_AND_UX_GUIDELINES.md

The native C++ build and JUCE setup will be documented in native/README.md once integrated and verified.

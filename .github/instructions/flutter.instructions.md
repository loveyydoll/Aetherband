---
applyTo: "**/*.dart, **/pubspec.yaml, **/analysis_options.yaml"
---

# Legacy Flutter / Dart FFI — Migration Reference Only

Flutter and Dart are no longer the target desktop architecture for Aetherband. This file is retained only to help agents safely inspect or temporarily maintain the legacy implementation during the C++ migration.

- Do not expand the Flutter frontend as the long-term product UI unless the project owner explicitly reverses the C++ migration decision.
- Before touching legacy code, read `AGENTS.md`, `docs/CPP_MIGRATION_PLAN.md`, and `docs/PROJECT_STATE.md`.
- Rust and Flutter code may be used to understand existing behavior, but do not assume that behavior is verified on hardware.
- Avoid unrelated cleanup or wholesale deletion of the legacy stack during migration.
- Any bug fix needed to preserve a useful reference should be focused and tested where possible.
- Do not introduce new Flutter/Dart features as part of the C++ target implementation.
- All new core audio runtime, DSP and target UI work belongs in the native C++ architecture unless an approved migration task explicitly says otherwise.

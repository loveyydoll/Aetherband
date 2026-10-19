---
applyTo: "**/*.dart, **/pubspec.yaml, **/analysis_options.yaml"
---

# Legacy Flutter/Dart — Migration Reference Only

Flutter and Dart are not the target application stack. The committed target is C++/JUCE under ADR-008.

- Do not add new product features to Flutter/Dart.
- Keep this code as a migration and behavioral reference until the corresponding C++/JUCE workflow passes acceptance criteria.
- Make focused legacy maintenance changes only when specifically requested or needed to compare behavior.
- Do not assume legacy behavior is verified on hardware.
- Do not delete the legacy stack wholesale or remove its history.
- Do not extend the old C ABI/Dart FFI as the target integration boundary.
- For migration work, read AGENTS.md, docs/CPP_MIGRATION_PLAN.md, and docs/PROJECT_STATE.md.

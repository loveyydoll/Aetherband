---
applyTo: "**/*.rs, **/Cargo.toml, **/Cargo.lock, **/build.rs"
---

# Legacy Rust — Migration Reference Only

Rust is not the target language for Aetherband's active application, audio runtime, or DSP. C++/JUCE is the committed direction.

- Do not add Rust-first product features unless a task explicitly requires legacy maintenance.
- Preserve the old engine during migration for behavior comparison; do not delete it wholesale.
- Inspect source and tests before treating documentation as evidence.
- Port validated behavior to C++/JUCE rather than mechanically translating source.
- Identify thread ownership and all code reachable from the legacy real-time callback.
- Preserve old contracts only where needed for reference/testing; do not extend the C ABI/Dart FFI as the target architecture.
- Never perform I/O, unpredictable allocation/deallocation, blocking calls, or contended locking in a real-time callback.
- Do not claim platform/device support without relevant tests.
- For target work, read AGENTS.md, docs/CPP_MIGRATION_PLAN.md, and docs/PROJECT_STATE.md.

---
applyTo: "**/*.rs, **/Cargo.toml, **/Cargo.lock, **/build.rs"
---

# Legacy Rust Engineering — Migration Reference Only

Rust is no longer the target language for Aetherband's active audio runtime or DSP architecture. These rules remain for safe inspection, focused maintenance and behavioral comparison while the C++ migration is underway.

- Read `AGENTS.md`, `docs/CPP_MIGRATION_PLAN.md`, `docs/PROJECT_STATE.md`, and the relevant legacy module before editing.
- Do not add new Rust-first product features unless a task explicitly requires maintaining the reference implementation.
- Do not delete the legacy engine wholesale; it is a source of behavioral reference until C++ replacements meet acceptance criteria.
- When examining old behavior, verify it against tests and actual source rather than assuming a documented feature is complete.
- Identify thread ownership and whether a function is reachable from the real-time audio callback.
- Preserve existing contracts only where they are needed for legacy testing or behavioral comparison; do not extend the C ABI/Dart FFI as the target architecture.
- Never perform file/network I/O, unpredictable allocation, blocking calls or contended locking in any real-time audio callback.
- Add or update tests for any legacy behavior changed, and report the platform and test evidence.
- Do not claim Windows/macOS runtime or audio hardware support without testing the relevant platform.
- Keep changes focused; port validated behavior to the native C++ target instead of mechanically translating source.

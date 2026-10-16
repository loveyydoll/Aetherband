---
applyTo: "**/*.rs, **/Cargo.toml, **/Cargo.lock, **/build.rs"
---

# Rust Engineering Rules

## Before editing
- Read root `AGENTS.md`, `docs/AI_WORKFLOW.md`, the relevant module, its callers, tests, workspace manifest and lockfile.
- Confirm the active Rust edition, toolchain, features and supported targets from repository files. Do not assume versions from old docs.
- Identify thread ownership and whether a function is reachable from the real-time audio callback.

## Code quality
- Prefer explicit types, small functions, meaningful domain errors and readable ownership flow.
- Use existing dependencies and established patterns where appropriate. New crates require a documented reason, licence, maintenance assessment and alternatives considered.
- Do not add `unsafe` without documenting the safety invariant, aliasing/lifetime assumptions, thread-safety assumptions and how they are tested.
- Avoid `unwrap()`, `expect()`, panics and unchecked indexing in externally influenced paths and callback-reachable code.
- Do not silence warnings or use broad `allow` attributes to evade CI. Explain narrowly scoped exceptions.
- Keep public APIs and error semantics stable unless a breaking change is intentional and documented.

## FFI and generated bindings
- Treat the C ABI as a public contract. Review ownership, pointer validity, string encoding, nullability, struct layout, error mapping and thread safety.
- Pair exported API changes with csbindgen regeneration and C# interop review. Never hand-edit generated output unless repository instructions explicitly require it.
- Ensure every resource has one clear owner and a defined release path, including failure and shutdown paths.

## Verification
Run from the workspace root when the toolchain and native prerequisites are available:
```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
```
- Report each command and its actual result separately.
- If toolchain/native dependencies are unavailable, say so; do not infer success.
- For concurrency and audio changes, add regression tests for error paths, saturation, shutdown and lifecycle—not just the happy path.

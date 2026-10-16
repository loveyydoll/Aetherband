---
applyTo: "**/*.cs, **/*.axaml, **/*.csproj, **/*.sln, **/*.slnx, **/Directory.Build.*"
---

# C# / .NET / Avalonia Rules

> **Transition status:** This is the existing audio-connected frontend, retained while Flutter is implemented. Flutter/Dart is the mandatory long-term desktop UI (see `docs/FLUTTER_DESKTOP_MIGRATION.md`). Keep the Avalonia app correct/buildable during migration, but do not silently redefine the product's target UI or implement all future frontend work only in C# by default. The Rust engine and C ABI remain shared.

## Verify the project first
- Inspect the actual `.sln` / `.slnx`, `.csproj`, `global.json`, package references and generated-code setup before choosing commands or framework assumptions.
- Repository documentation may contain old project names and target-framework versions. The project files are authoritative.
- Follow the current UI architecture and naming conventions; do not introduce a new MVVM framework or state-management system without an explicit design decision.
- Changes needed to keep the current real-audio workflows operational may remain in Avalonia during migration. New UI behavior should be designed with the Flutter target and shared C ABI in mind; do not remove or break the transition app before parity is verified.

## UI and application code
- Keep views focused on presentation and ViewModels/services focused on state and behaviour.
- Use `async` / `await` for I/O and long-running operations. Do not synchronously block the UI thread with `.Wait()`, `.Result`, sleeps or long loops.
- Handle cancellation, disposal, device changes and native errors explicitly.
- Avoid fire-and-forget tasks unless exceptions and lifetime are handled.
- Keep UI state consistent with native-engine state; surface actionable errors rather than silently ignoring failed commands.
- Ensure event subscriptions, native handles, streams and other resources have clear disposal paths.
- Do not hand-edit generated interop files or duplicate native declarations when generated bindings are the source of truth.

## Interop
- Validate ABI types, integer widths, enum values, pointer ownership, string lifetime and null handling at the boundary.
- Never assume a native call succeeded solely because it returned; inspect and map the documented result.
- Do not block the UI waiting for audio-thread completion.

## Verification
- Use the target framework and solution path found in the current repository; do not copy stale commands from documentation.
- Run restore, build, tests and formatting/analyzers where configured. Report actual outputs and skipped checks independently.
- Add tests for error handling, cancellation, lifecycle/disposal and native failure paths when relevant.

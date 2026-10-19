# Changelog

All notable changes to Aetherband are recorded here. This is a development changelog, not a substitute for Git tags or GitHub Releases. Entries describe repository changes and do not imply that runtime behavior has been independently verified.

## Unreleased

### Architecture and documentation

- **2026-10-19 — Native C++/JUCE direction:** Accepted ADR-008, making C++20+ and JUCE the committed application foundation, with CMake and Windows/macOS as required targets. The target owns DSP graph execution, processor lifecycle, routing, transport, and offline-rendering semantics.
- **2026-10-19 — Migration documentation:** Aligned the README, architecture, vision, project state, roadmap, feature tracker, migration plan, audio-engine contract, project-format notes, contributor/agent guidance, and language-specific instructions with the C++/JUCE direction.
- **Migration safety:** Rust/C ABI/Flutter/Dart are retained as legacy references until the native replacement meets acceptance criteria; they are not target architecture.

### Important status note

The C++ foundation currently contains a CMake/C++20 scaffold, a planar float audio buffer, a basic additive mixer, and initial unit tests. The foundation has not been verified on both Windows and macOS in this documentation pass. A JUCE application, device playback, transport, executing DSP graph, project persistence, media workflow, HypnoSynth port, and usable DAW workflow remain to be implemented and tested.

Historical entries below may describe the legacy Flutter/Rust implementation and should not be read as proof of native C++ feature parity.

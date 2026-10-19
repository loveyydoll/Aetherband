# Aetherband — Current Next Steps

**Reviewed:** 2026-10-19  
**Authority:** Execution queue for the committed C++/JUCE architecture in ADR-008.

## Immediate sequence

1. **Audit legacy behavior.** Inventory engine, UI workflows, tests, session persistence, media, instruments, and limitations. Record evidence instead of assuming old documentation is current.
2. **Integrate JUCE.** Establish reproducible CMake dependency management and record JUCE version, modules, licence obligations, and platform prerequisites.
3. **Prove Windows and macOS.** Build and launch a minimal JUCE app on each platform; enumerate devices; open, play a known signal, stop, close, and repeat lifecycle tests.
4. **Define runtime contracts.** Specify buffers, sample rate, block size, channels, transport, bounded command flow, ownership, errors, and teardown.
5. **Implement real DSP execution.** Start with gain/pan and summing; add offline known-signal tests and graph validation.
6. **Deliver the first usable DAW slice.** WAV import, multitrack arrangement/playback/mix, save/reopen, and WAV export.
7. **Port HypnoSynth.** Use behavior audits and regression fixtures; add MIDI and other production features after the vertical slice is reliable.

## Guardrails

- Do not replace JUCE with Flutter/Tauri or reopen the framework decision without explicit owner direction.
- Do not delete Rust/Flutter/Dart wholesale; retain them until acceptance criteria pass.
- Do not report platform/device support without evidence.
- WAV is the only legacy format reported as tested; validate others individually.
- Keep the feature tracker and project state aligned with actual code and tests.

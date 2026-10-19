# Product Vision: Aetherband

## Vision

Aetherband is a free, open-source desktop DAW designed to combine an expressive, arrangement-first creative workspace with reliable native audio processing. The product prioritizes low-friction songwriting, deep editing when needed, portability, and transparent engineering.

## Architecture decision

- **Desktop UI:** Flutter + Dart.
- **Audio engine and DSP:** Rust.
- **Native boundary:** versioned C ABI consumed through Dart FFI.
- **Current target:** Windows only by owner direction; other platforms are deferred.

Flutter is the selected frontend because the project needs fine-grained control over timeline, waveform, mixer and instrument UI; rapid visual iteration; consistent rendering across supported desktops; and room to profile and optimize custom DAW interactions. This does not imply automatic performance wins: rendering and large-session behavior must be measured.

The previous Avalonia/C# frontend has been removed from the desktop target. The product has one intended desktop UI to avoid duplicating frontend work and splitting feature parity across frameworks.

## Core principles

1. **Real-time audio integrity:** no UI work, file I/O, allocation or blocking operation in the audio callback.
2. **Intuitive by default, deep on demand:** a clear arrangement workflow with precise tools when needed.
3. **Desktop-first:** keyboard, mouse, high-DPI and multi-window workflows are first-class.
4. **Native audio core:** decoding, DSP, mixing and device I/O remain in Rust.
5. **Explicit FFI:** documented ABI, validated layouts, clear ownership and real error reporting.
6. **Non-destructive editing:** imported sources are preserved and project state is recoverable.
7. **Honest capability claims:** mock UI is not a substitute for implemented and tested engine behavior.
8. **Open source:** GPLv3, reproducible builds and no proprietary lock-in.

## Long-term capabilities

- Reliable multitrack playback, recording, project save/load and export.
- Waveforms, non-destructive editing, undo/redo and advanced mixing.
- MIDI editing, built-in instruments and native effects.
- Plugin hosting after compatibility, legal and crash-containment review.
- Shared project format and possible future companion clients, only after the desktop product is stable.

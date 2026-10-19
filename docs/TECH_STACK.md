# Aetherband technology choices

**Current target:** Windows desktop only. Other platforms are deferred by owner direction. Check the repository manifests for exact dependency versions; this document explains subsystem choices rather than promising support or feature parity.

| Subsystem | Technology | Why it fits this product |
|---|---|---|
| Audio engine, decoder workers, mixer and DSP | Rust | The callback needs bounded work, no garbage-collector pauses, and explicit ownership across the device and control threads. Rust is already the tested core and has direct CPAL, Symphonia and real-time queue libraries. |
| Windows audio device I/O | CPAL 0.18.2 | The Windows engine uses CPAL's WASAPI backend and the device's native output sample format. A local stream lifecycle test found clean shutdown after upgrading from 0.15.3. |
| Audio decoding and sample-rate conversion | Symphonia and Rubato | Symphonia decodes the configured media formats; Rubato is used for worker-side conversion. Support is limited to formats verified by tests and actual media, not every format a dependency can theoretically parse. |
| Real-time communication | `rtrb` and bounded standard-library control channel | SPSC queues carry audio-thread work without locks; control operations remain serialized away from the callback. |
| Native/UI boundary | Versioned C ABI and Dart FFI | The boundary keeps audio buffers and Rust internals out of Flutter while allowing the UI to send bounded commands and read telemetry. ABI 0.11.0 is checked against the Dart adapter at startup. |
| Desktop interface | Flutter and Dart | The existing product UI, custom arrangement and instrument panels already use Flutter. Keeping it avoids an unneeded frontend migration while Rust stays responsible for time-critical audio. |

## Why these languages

Rust remains the right fit for the low-level audio subsystem because the callback must not allocate, block, perform file I/O or wait on Dart's garbage-collected runtime. Rust's ownership model also helps keep the device stream, decoder workers and control-thread lifecycle explicit. C++/JUCE could provide a mature plugin and audio framework, but replacing the working Rust engine would add a large migration and licensing surface without solving a demonstrated Windows bug faster than the CPAL repair.

Dart remains the right fit for the interface because Flutter already owns the workspace UI, input handling and timeline rendering. Moving the UI to Rust would replace working Flutter panels and require rebuilding desktop interaction infrastructure. Dart communicates with the engine through the small C ABI; it does not process audio samples.

The C ABI is an integration boundary, not a third product implementation language. It exposes fixed-width values and opaque engine handles so Rust can keep ownership of audio resources and Dart can keep ownership of presentation state. No second implementation of DSP or arrangement scheduling belongs on the UI side.

## Source reuse and licensing

The adapted Soundcraft ADSR envelope is attributed in `third_party/soundcraft/README.md` and distributed under its upstream MIT license, preserved in `third_party/soundcraft/LICENSE-MIT`. HypnoSynth's oscillators, filtering, modulation, delay, presets and interface are original Aetherband work.

## Verification boundary

The current target is Windows. Rust unit and callback tests, C ABI release builds, Flutter analysis/tests and the Windows desktop build cover separate parts of the product. A successful callback smoke test confirms nonzero samples reached the WASAPI callback; it does not prove a person heard output through speakers. Keep those verification results separate in release notes and project status.

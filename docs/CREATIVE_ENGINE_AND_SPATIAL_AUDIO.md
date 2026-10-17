# Aetherband: Creative Engine and Spatial Audio Direction

## Vision

Aetherband aims to unite four workflows in one open creative platform:

- **Production:** recording, arrangement, MIDI, instruments, effects, automation, and project management.
- **Performance:** clip-oriented creation, improvisation, and live control.
- **Precision editing and mixing:** detailed audio editing, routing, buses, metering, and reliable sessions.
- **Visual programming:** user-built instruments, processors, modulation systems, and generative musical tools.

These are product inspirations, not a claim of feature parity with any existing application. The goal is one project model and one extensible engine, rather than four disconnected applications.

## Architecture principles

1. **One shared audio engine.** The timeline, mixer, instruments, spatial routing, and custom DSP should ultimately use shared signal-processing and scheduling foundations.
2. **Typed graphs.** Audio, control/modulation, musical events, and analysis data have distinct connection types and execution rules.
3. **Real-time safety.** Graph construction, file I/O, compilation, allocation-heavy work, and UI communication stay off the audio callback. The callback executes a prepared, bounded plan.
4. **Extensibility by design.** Core nodes first; then a documented user-DSP path and external extension SDK with explicit compatibility and resource constraints.
5. **Portable projects.** Store stable IDs, versioned node/parameter definitions, channel layouts, spatial metadata, and migration information in project data.
6. **Evidence over claims.** Mark each capability as designed, implemented, automated-tested, or manually verified. Do not describe architectural foundations as finished user-facing features.

## Spatial audio is a first-class architectural concern

Spatial audio must not be bolted on after a stereo-only engine and project format have become permanent. The current engine is stereo-oriented; the first implementation steps should introduce a spatial model without claiming that multichannel spatial rendering is already available.

### Spatial model

- A track, bus, instrument, and output should eventually declare a channel format/layout rather than assuming two channels everywhere.
- A spatial source should have a position and, later, orientation, size/spread, distance behaviour, and optional automation.
- Audio routing must support explicit channel mapping and format conversion, with errors for unsupported or ambiguous layouts.
- Preserve conventional mono/stereo production as the simple default.
- Keep **speaker-based multichannel layouts** separate from **Ambisonic component layouts**. Ambisonics needs a defined component ordering and normalization convention; a four-channel buffer alone is not a complete specification.
- Separate spatial source representation from the output renderer. The same project could later target stereo binaural monitoring, supported speaker layouts, or a compatible immersive delivery pipeline.
- Make render/monitor configuration explicit. Monitoring format and export format are different concerns.

### Suggested implementation sequence

1. **Model and test the metadata.** Introduce channel-layout types and a coordinate convention for spatial positions. This is the scope of the initial code foundation; it does not change the existing mixer.
2. **Make the engine format-aware.** Replace hard-coded stereo assumptions with explicit input/output channel formats and safe mapping. Preserve existing stereo behaviour with regression tests.
3. **Add multichannel buses and routing.** Support layout-aware track and bus connections, meters, and deterministic downmix/upmix policies.
4. **Add object panning.** Implement speaker-layout-aware source panning, including elevation where appropriate, with documented behavior for unsupported layouts.
5. **Add binaural monitoring.** Evaluate HRTF-based rendering, head-tracking as an optional future feature, latency, and CPU cost.
6. **Evaluate immersive delivery.** Research standards, licensing, metadata, renderer interoperability, and export requirements before promising Dolby Atmos authoring or delivery. A generic spatial engine is not automatically an Atmos renderer or a certified Atmos workflow.

### Spatial audio testing requirements

- Test layout channel counts and mapping, including silence in unused channels.
- Test stereo regression behaviour so existing sessions do not change unexpectedly.
- Verify speaker ordering, coordinate conventions, and pan positions with deterministic test signals.
- Test finite-value validation, clipping/headroom, downmix behaviour, and unsupported layouts.
- Measure callback cost and latency with representative multichannel sessions.
- Test project round-tripping so spatial metadata survives save/reopen.

## Synthesis and visual programming

The long-term synthesizer should have three views over the same patch:

- **Instrument mode:** approachable controls, presets, performance, and macro parameters.
- **Graph/laboratory mode:** editable nodes and connections for audio, control, and events.
- **Developer mode:** custom DSP and extensions through a constrained and documented interface.

Initial node families can include oscillators, envelopes, LFOs, filters, noise, gain, waveshaping, delays, and event utilities. Later families may include wavetable, FM, additive, sample-based, granular, spectral, and physical-modeling methods.

Feedback and cyclic modulation require explicit semantics and stability protections. Do not permit arbitrary graph cycles to run without validation.

User-authored DSP should not execute as unrestricted native code on the real-time thread. Evaluate a constrained language or compiler-backed system (Faust is one candidate) and, later, sandboxing for third-party code. Sandboxing alone does not guarantee real-time safety; imports, allocations, execution budgets, and failure behaviour must be controlled.

## Delivery order

### Before the first Beta
- Stabilize current playback, import/arrangement, project persistence, and export workflows.
- Keep spatial audio and modular synthesis architecture documented and testable.
- Avoid diverting the first Beta into a full multichannel renderer or visual programming environment.

### Early post-Beta
- Establish a native instrument and stable parameter/event model.
- Build a typed graph proof of concept and test prepared graph execution.
- Make channel formats explicit in the engine and session model before expanding spatial routing.

### Subsequent releases
- Add graph editing, reusable subgraphs, more synthesis methods, and user DSP.
- Add multichannel buses and spatial panning, then binaural monitoring.
- Evaluate immersive interchange/export against real technical and licensing requirements.
- Develop an external extension SDK only after the internal node contract stabilizes.

## Current status

The spatial module currently provides foundational ChannelLayout metadata and a normalized Cartesian SpatialPosition type with tests. It does **not** render spatial audio, change the mixer, configure multichannel devices, or provide Atmos support. Those require separate implementation and end-to-end verification.

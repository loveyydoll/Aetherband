# SoundCraft source attribution

`core/src/envelope.rs` adapts the `Stage`, `AdsrRates` and `Adsr` implementations from
[`crates/dsp/src/plugins/synth.rs`](https://github.com/storytold/soundcraft/blob/2e9ad2f4215bd36e7edf30579e8ce520d5ce67c7/crates/dsp/src/plugins/synth.rs).

Copyright (c) 2026 ArtCraft Team and the SoundCraft contributors.
Used under the upstream MIT option. The complete licence is in `LICENSE-MIT`;
`UPSTREAM-NOTICE` preserves upstream attribution and trademark boundaries.

Changes: extracted the envelope from the plugin framework, inlined milliseconds
to samples conversion, and adjusted module visibility. No ArtCraft branding,
logos, assets or third-party plugins are included. Aetherband remains GPL-3.0.

The native device-format dispatch was also compared with SoundCraft's playback
implementation; Aetherband uses its existing CPAL 0.15 API and engine ownership.
The remainder of HypnoSynth is original Aetherband implementation.

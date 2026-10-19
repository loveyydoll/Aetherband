//! Opt-in test for a real Windows output device.
//!
//! Set `AETHERBAND_AUDIO_SMOKE=1` to play a quiet HypnoSynth note and verify
//! that nonzero samples reach the WASAPI callback. A normal test run skips the
//! device interaction so headless CI remains deterministic.

#![cfg(windows)]

use daw_core::DAWEngine;
use std::{thread, time::Duration};

#[test]
fn default_device_renders_hypnosynth_and_shuts_down() {
    if std::env::var("AETHERBAND_AUDIO_SMOKE").ok().as_deref() != Some("1") {
        eprintln!("skipped; set AETHERBAND_AUDIO_SMOKE=1 to use a real output device");
        return;
    }

    let mut engine = DAWEngine::new().expect("open the default Windows audio output");
    assert!(engine.synth_event(0, 60, 0.25), "queue a quiet C4 note");

    let mut peak = None;
    for _ in 0..40 {
        thread::sleep(Duration::from_millis(20));
        if let Some(frame) = engine.poll_telemetry() {
            assert_eq!(frame.device_error_flag, 0, "audio stream reported an error");
            if frame.peak_left > 0.0 || frame.peak_right > 0.0 {
                peak = Some((frame.peak_left, frame.peak_right));
                break;
            }
        }
    }

    assert!(peak.is_some(), "HypnoSynth output stayed silent");
    engine.synth_event(1, 60, 0.0);
    drop(engine); // Stream teardown must remain clean after a live callback.
}

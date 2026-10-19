//! Opt-in test for a real Windows output device.
//!
//! Set `AETHERBAND_AUDIO_SMOKE=1` to play a quiet HypnoSynth note and a
//! scheduled pattern region, verifying nonzero samples reach the WASAPI
//! callback. A normal test run skips device interaction for headless CI.

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

    // Leave the live note's release tail before checking the arrangement
    // scheduler, so the signal must come from the pattern region.
    thread::sleep(Duration::from_millis(300));
    engine.configure_transport(120.0, false, false);
    let mut notes = [None; 16];
    notes[0] = Some(67);
    assert!(engine.set_sequence_region(1, 0.2, notes));
    assert!(engine.play());
    let mut arranged_peak = None;
    for _ in 0..60 {
        thread::sleep(Duration::from_millis(20));
        if let Some(frame) = engine.poll_telemetry() {
            assert_eq!(frame.device_error_flag, 0, "audio stream reported an error");
            if frame.playhead_frame as f64 / engine.output_sample_rate() as f64 >= 0.2
                && (frame.peak_left > 0.0 || frame.peak_right > 0.0)
            {
                arranged_peak = Some((frame.peak_left, frame.peak_right));
                break;
            }
        }
    }
    assert!(arranged_peak.is_some(), "arrangement pattern stayed silent");
    engine.stop();
    engine.remove_sequence_region(1);
    drop(engine); // Stream teardown must remain clean after a live callback.
}

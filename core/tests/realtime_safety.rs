//! Real-time audio safety test suite.
//!
//! Enforces the Real-Time Thread Contract using assert_no_alloc to guarantee
//! that the audio processor performs zero heap allocations during playback.

use assert_no_alloc::*;
use daw_core::audio::AudioProcessor;
use daw_core::ringbuf::{create_engine_queues, EngineCommand};

#[cfg(debug_assertions)]
#[global_allocator]
static A: AllocDisabler = AllocDisabler;

#[test]
fn test_audio_callback_zero_allocations() {
    let (mut ui, audio) = create_engine_queues(1024, 2048);
    let mut processor = AudioProcessor::new(48000.0, audio);

    // Pre-allocate a 128-frame stereo buffer (256 samples)
    let mut buffer = [0.0f32; 256];

    // Prime the processor
    ui.cmd_producer.push(EngineCommand::Play).unwrap();
    ui.cmd_producer
        .push(EngineCommand::SetTestTone {
            enabled: true,
            frequency_hz: 440.0,
        })
        .unwrap();
    ui.cmd_producer
        .push(EngineCommand::SetMasterVolume {
            target_gain: 0.8,
            ramp_frames: 256,
        })
        .unwrap();

    // Execute 100,000 consecutive audio blocks inside the allocation-forbidden zone
    // (Simulates ~4.5 minutes of continuous 48kHz audio processing at 128 frames)
    assert_no_alloc(|| {
        for _ in 0..100_000 {
            processor.process_interleaved(&mut buffer, 2);
        }
    });

    // Verification: buffer must have valid audio data
    assert!(buffer.iter().any(|&s| s != 0.0));
}

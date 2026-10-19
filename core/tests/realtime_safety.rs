//! Real-time audio safety test suite.
//!
//! Enforces the Real-Time Thread Contract using assert_no_alloc to guarantee
//! that the audio processor performs zero heap allocations during playback.

use assert_no_alloc::*;
use daw_core::audio::AudioProcessor;
use daw_core::ringbuf::{
    create_engine_queues, create_stream_queue, DecodedBlock, EngineCommand, TrackId,
};
use daw_core::track::TrackPlayer;

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

    // Exercise block turnover in the same allocation-forbidden callback loop.
    let (mut stream_producer, stream_consumer) = create_stream_queue(8);
    for _ in 0..4 {
        let mut block = DecodedBlock::silent(128);
        block.samples.fill(0.25);
        stream_producer.push(block).unwrap();
    }
    let player = Box::new(TrackPlayer::new(TrackId(42), stream_consumer, 1.0, 512));
    ui.cmd_producer
        .push(EngineCommand::AddTrack {
            player_ptr: Box::into_raw(player) as usize,
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
    let retired_blocks = std::iter::from_fn(|| ui.retired_blocks.pop().ok()).count();
    assert!(
        retired_blocks >= 3,
        "decoded blocks should be recycled off-thread"
    );
}

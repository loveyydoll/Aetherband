//! Audio processing engine and real-time callback processor.
//!
//! Enforces the Hard Real-Time Thread Contract: zero allocations, zero locks, zero blocking I/O.

use crate::dsp::{GainRamp, LevelMeter, SineOscillator};
use crate::ringbuf::{AudioEndpoints, EngineCommand, TelemetryFrame};
use rtrb::{Consumer, Producer};

/// The real-time audio callback processor.
///
/// Executes inside the high-priority OS audio thread callback.
pub struct AudioProcessor {
    cmd_consumer: Consumer<EngineCommand>,
    telemetry_producer: Producer<TelemetryFrame>,
    oscillator: SineOscillator,
    master_gain: GainRamp,
    meter: LevelMeter,
    sample_rate: f32,
    playhead_frame: i64,
    is_playing: bool,
    test_tone_enabled: bool,
    // Pre-allocated scratch buffers for stereo metering
    scratch_left: Vec<f32>,
    scratch_right: Vec<f32>,
}

impl AudioProcessor {
    /// Maximum expected frames per audio callback block.
    pub const MAX_BLOCK_FRAMES: usize = 2048;

    /// Creates a new `AudioProcessor` with pre-allocated memory.
    pub fn new(sample_rate: f32, endpoints: AudioEndpoints) -> Self {
        Self {
            cmd_consumer: endpoints.cmd_consumer,
            telemetry_producer: endpoints.telemetry_producer,
            oscillator: SineOscillator::new(sample_rate, 440.0),
            master_gain: GainRamp::new(1.0),
            meter: LevelMeter::new(),
            sample_rate,
            playhead_frame: 0,
            is_playing: false,
            test_tone_enabled: true, // Enabled by default for MVP verification
            scratch_left: vec![0.0; Self::MAX_BLOCK_FRAMES],
            scratch_right: vec![0.0; Self::MAX_BLOCK_FRAMES],
        }
    }

    /// Returns the active audio sample rate in Hz.
    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }

    /// Returns true if the transport is actively playing.
    pub fn is_playing(&self) -> bool {
        self.is_playing
    }

    /// Handles incoming commands from the UI control thread.
    #[inline]
    fn handle_commands(&mut self) {
        while let Ok(cmd) = self.cmd_consumer.pop() {
            match cmd {
                EngineCommand::Play => {
                    self.is_playing = true;
                }
                EngineCommand::Pause => {
                    self.is_playing = false;
                }
                EngineCommand::Stop => {
                    self.is_playing = false;
                    self.playhead_frame = 0;
                    self.oscillator.reset();
                }
                EngineCommand::Seek(frame) => {
                    self.playhead_frame = frame.max(0);
                }
                EngineCommand::SetMasterVolume {
                    target_gain,
                    ramp_frames,
                } => {
                    self.master_gain.set_target(target_gain, ramp_frames);
                }
                EngineCommand::SetTestTone {
                    enabled,
                    frequency_hz,
                } => {
                    self.test_tone_enabled = enabled;
                    self.oscillator.set_frequency(frequency_hz);
                }
            }
        }
    }

    /// Processes an interleaved stereo audio output buffer directly provided by the hardware callback.
    ///
    /// # Real-Time Safety
    /// This function performs zero heap allocations and uses no locks.
    pub fn process_interleaved(&mut self, output: &mut [f32], channels: usize) {
        // 1. Process all pending UI commands
        self.handle_commands();

        let frames = output.len() / channels;
        let meter_frames = frames.min(Self::MAX_BLOCK_FRAMES);

        // 2. Synthesize audio samples
        for f in 0..frames {
            let sample = if self.is_playing && self.test_tone_enabled {
                self.oscillator.next_sample()
            } else {
                0.0
            };

            let gain = self.master_gain.next_gain();
            let final_sample = sample * gain;

            // Write to output channels
            for ch in 0..channels {
                output[f * channels + ch] = final_sample;
            }

            // Copy to scratch buffer for metering (first 2 channels)
            if f < meter_frames {
                self.scratch_left[f] = final_sample;
                self.scratch_right[f] = final_sample;
            }
        }

        if self.is_playing {
            self.playhead_frame += frames as i64;
        }

        // 3. Compute real-time metering
        let (peak_l, peak_r, rms_l, rms_r) = self.meter.process_block(
            &self.scratch_left[..meter_frames],
            &self.scratch_right[..meter_frames],
        );

        // 4. Send telemetry frame to UI (lossy - drop if queue is full)
        let telemetry = TelemetryFrame {
            peak_left: peak_l,
            peak_right: peak_r,
            rms_left: rms_l,
            rms_right: rms_r,
            playhead_frame: self.playhead_frame,
            is_playing: self.is_playing,
            device_error_flag: 0,
        };

        // If telemetry queue is full, push() returns Err, which we safely ignore to maintain real-time safety
        let _ = self.telemetry_producer.push(telemetry);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ringbuf::create_engine_queues;

    #[test]
    fn test_audio_processor_playback_and_metering() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48000.0, audio);

        let mut buffer = vec![0.0f32; 256]; // 128 stereo frames

        // Initially stopped: output should be silence
        processor.process_interleaved(&mut buffer, 2);
        assert_eq!(buffer[0], 0.0);
        let frame1 = ui.telemetry_consumer.pop().unwrap();
        assert!(!frame1.is_playing);

        // Send Play command
        ui.cmd_producer.push(EngineCommand::Play).unwrap();

        // Next block should contain active test tone
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().any(|&s| s != 0.0));

        // Verify telemetry frame received by UI reflects playback
        let frame2 = ui.telemetry_consumer.pop().unwrap();
        assert!(frame2.is_playing);
        assert!(frame2.peak_left > 0.0);
    }
}

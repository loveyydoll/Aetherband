//! Lock-free Single-Producer Single-Consumer (SPSC) command and telemetry queues.
//!
//! Provides wait-free, non-blocking communication between the UI control thread
//! and the hard real-time audio thread.

use rtrb::{Consumer, Producer, RingBuffer};

/// Commands sent from the UI/Control thread to the real-time Audio thread.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum EngineCommand {
    /// Start audio playback.
    Play,
    /// Pause audio playback.
    Pause,
    /// Stop audio playback and rewind playhead to 0.
    Stop,
    /// Seek playhead to sample index.
    Seek(i64),
    /// Set master volume target gain with de-zippering frame duration.
    SetMasterVolume {
        target_gain: f32,
        ramp_frames: usize,
    },
    /// Enable or disable the diagnostic test tone oscillator.
    SetTestTone {
        enabled: bool,
        frequency_hz: f32,
    },
}

/// Telemetry and metering frame sent from the real-time Audio thread to the UI thread.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct TelemetryFrame {
    /// Linear peak amplitude on Left channel [0.0, 1.0+].
    pub peak_left: f32,
    /// Linear peak amplitude on Right channel [0.0, 1.0+].
    pub peak_right: f32,
    /// Root-Mean-Square level on Left channel.
    pub rms_left: f32,
    /// Root-Mean-Square level on Right channel.
    pub rms_right: f32,
    /// Current playhead position in absolute audio samples.
    pub playhead_frame: i64,
    /// Whether the transport is currently playing.
    pub is_playing: bool,
    /// Non-zero if an audio device error occurred.
    pub device_error_flag: u8,
}

/// Pair of producers for sending commands to the audio thread and receiving telemetry from it.
pub struct UIEndpoints {
    pub cmd_producer: Producer<EngineCommand>,
    pub telemetry_consumer: Consumer<TelemetryFrame>,
}

/// Pair of consumers/producers used exclusively on the real-time audio thread.
pub struct AudioEndpoints {
    pub cmd_consumer: Consumer<EngineCommand>,
    pub telemetry_producer: Producer<TelemetryFrame>,
}

/// Creates the lock-free ring buffer communication endpoints.
pub fn create_engine_queues(
    cmd_capacity: usize,
    telemetry_capacity: usize,
) -> (UIEndpoints, AudioEndpoints) {
    let (cmd_producer, cmd_consumer) = RingBuffer::new(cmd_capacity);
    let (telemetry_producer, telemetry_consumer) = RingBuffer::new(telemetry_capacity);

    (
        UIEndpoints {
            cmd_producer,
            telemetry_consumer,
        },
        AudioEndpoints {
            cmd_consumer,
            telemetry_producer,
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_queue_push_and_pop() {
        let (mut ui, mut audio) = create_engine_queues(16, 16);

        // UI pushes command
        assert!(ui.cmd_producer.push(EngineCommand::Play).is_ok());

        // Audio pops command
        let cmd = audio.cmd_consumer.pop();
        assert_eq!(cmd, Ok(EngineCommand::Play));

        // Audio pushes telemetry
        let frame = TelemetryFrame {
            peak_left: 0.8,
            peak_right: 0.75,
            playhead_frame: 1024,
            is_playing: true,
            ..Default::default()
        };
        assert!(audio.telemetry_producer.push(frame).is_ok());

        // UI pops telemetry
        let received = ui.telemetry_consumer.pop();
        assert_eq!(received, Ok(frame));
    }
}

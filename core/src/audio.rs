//! Real-time audio callback processor.
//!
//! Enforces the Hard Real-Time Thread Contract:
//! - Zero heap allocations
//! - Zero OS locks (wait-free SPSC ring buffers only)
//! - Zero blocking filesystem / network I/O

use crate::dsp::{GainRamp, LevelMeter, SineOscillator};
use crate::hypnosynth::HypnoSynth;
use crate::ringbuf::{AudioEndpoints, DecodedBlock, EngineCommand, TelemetryFrame};
use crate::track::{TrackPlayer, TrackSlots, MAX_TRACKS};
use rtrb::{Consumer, Producer};

/// Hard real-time audio callback processor.
///
/// All fields are pre-allocated at construction. `process_interleaved` must
/// never allocate, lock, or perform any blocking operation.
pub struct AudioProcessor {
    cmd_consumer: Consumer<EngineCommand>,
    telemetry_producer: Producer<TelemetryFrame>,
    retired_tracks: Producer<Box<TrackPlayer>>,
    retired_blocks: Producer<DecodedBlock>,
    // Fixed-capacity fallback when the control thread has not reclaimed returned players.
    pending_retired: [Option<Box<TrackPlayer>>; MAX_TRACKS],

    // DSP
    oscillator: SineOscillator,
    master_gain: GainRamp,
    meter: LevelMeter,
    synth: HypnoSynth,
    bpm: f32,
    metronome: bool,
    sequence: bool,
    sequence_note: Option<u8>,
    beat_phase: f64,
    click_remaining: usize,

    // State
    sample_rate: f32,
    playhead_frame: i64,
    is_playing: bool,
    test_tone_enabled: bool,

    // Multi-track players (owned by audio thread only)
    tracks: TrackSlots,

    // Pre-allocated scratch buffers (no alloc in callback)
    scratch_left: Vec<f32>,
    scratch_right: Vec<f32>,
}

impl AudioProcessor {
    /// Maximum expected stereo frames per audio callback block.
    pub const MAX_BLOCK_FRAMES: usize = 2048;

    /// Creates a new `AudioProcessor` with all memory pre-allocated.
    pub fn new(sample_rate: f32, endpoints: AudioEndpoints) -> Self {
        Self {
            cmd_consumer: endpoints.cmd_consumer,
            telemetry_producer: endpoints.telemetry_producer,
            retired_tracks: endpoints.retired_tracks,
            retired_blocks: endpoints.retired_blocks,
            pending_retired: std::array::from_fn(|_| None),
            oscillator: SineOscillator::new(sample_rate, 440.0),
            master_gain: GainRamp::new(0.8),
            meter: LevelMeter::new(),
            synth: HypnoSynth::new(sample_rate),
            bpm: 92.0,
            metronome: false,
            sequence: false,
            sequence_note: None,
            beat_phase: 0.0,
            click_remaining: 0,
            sample_rate,
            playhead_frame: 0,
            is_playing: false,
            test_tone_enabled: false, // Disabled by default now that track playback exists
            tracks: TrackSlots::new(),
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

    /// Provides mutable access to the track slot table so the engine
    /// controller can install new `TrackPlayer` instances before streaming.
    ///
    /// # Safety
    /// Must only be called from the control thread **before** the stream
    /// starts, or while the stream is paused/stopped. Never call during
    /// an active audio callback.
    pub fn tracks_mut(&mut self) -> &mut TrackSlots {
        &mut self.tracks
    }

    // ─────────────────────────────────────────────────────────────────────
    // Command handler (called at the top of every callback block)
    // ─────────────────────────────────────────────────────────────────────

    #[inline]
    fn flush_pending_retired(&mut self) {
        for slot in self.pending_retired.iter_mut() {
            let Some(player) = slot.take() else {
                continue;
            };
            match self.retired_tracks.push(player) {
                Ok(()) => {}
                Err(rtrb::PushError::Full(player)) => {
                    *slot = Some(player);
                    break;
                }
            }
        }
    }

    #[inline]
    fn has_pending_retirement_capacity(&self) -> bool {
        self.pending_retired.iter().any(Option::is_none)
    }

    #[inline]
    fn retire_track(&mut self, player: Box<TrackPlayer>) {
        match self.retired_tracks.push(player) {
            Ok(()) => {}
            Err(rtrb::PushError::Full(player)) => {
                if let Some(slot) = self.pending_retired.iter_mut().find(|slot| slot.is_none()) {
                    *slot = Some(player);
                } else {
                    // The command loop checks capacity before popping another command.
                    // This branch is defensive; intentionally leak rather than run a
                    // destructor/deallocation on the real-time thread.
                    let _ = Box::into_raw(player);
                    // This is unreachable while the command-loop capacity invariant holds.
                }
            }
        }
    }

    #[inline]
    fn handle_commands(&mut self) {
        use crate::ringbuf::EngineCommand::*;
        // Bound control work per callback so a burst of UI commands cannot
        // monopolize the real-time thread for an unbounded amount of time.
        const MAX_COMMANDS_PER_BLOCK: usize = 128;
        self.flush_pending_retired();
        for _ in 0..MAX_COMMANDS_PER_BLOCK {
            // If both retirement storage tiers are full, leave commands queued
            // until the control thread reclaims retired players.
            if !self.has_pending_retirement_capacity() {
                break;
            }
            let Ok(cmd) = self.cmd_consumer.pop() else {
                break;
            };
            match cmd {
                SynthEvent { event, key, value } => match event {
                    0 => self.synth.note_on(key as u8, value),
                    1 => self.synth.note_off(key as u8),
                    2 => self.synth.preset(key as u8),
                    3 => self.synth.parameter(key as u8, value),
                    4 => self.synth.panic(),
                    _ => (),
                },
                ConfigureTransport {
                    bpm,
                    metronome,
                    sequence,
                } => {
                    self.bpm = bpm;
                    self.metronome = metronome;
                    self.sequence = sequence;
                    if !sequence {
                        if let Some(note) = self.sequence_note.take() {
                            self.synth.note_off(note);
                        }
                    }
                }
                Play => {
                    self.is_playing = true;
                }
                Pause => {
                    self.is_playing = false;
                    self.synth.panic();
                    self.sequence_note = None;
                }
                Stop => {
                    self.is_playing = false;
                    self.playhead_frame = 0;
                    self.oscillator.reset();
                    self.synth.panic();
                    self.sequence_note = None;
                    self.beat_phase = 0.0;
                    self.click_remaining = 0;
                    self.tracks.reset_all();
                }
                Seek(frame) => {
                    self.playhead_frame = frame.max(0);
                    // Track seek is handled by the control thread restarting
                    // the decoder from the new position
                }
                SetMasterVolume {
                    target_gain,
                    ramp_frames,
                } => {
                    self.master_gain.set_target(target_gain, ramp_frames);
                }
                SetTestTone {
                    enabled,
                    frequency_hz,
                } => {
                    self.test_tone_enabled = enabled;
                    self.oscillator.set_frequency(frequency_hz);
                }
                SetTrackVolume {
                    track_id,
                    target_gain,
                    ramp_frames,
                } => {
                    if let Some(track) = self.tracks.get_mut(track_id) {
                        track.gain.set_target(target_gain, ramp_frames);
                    }
                }
                SetTrackPan { track_id, pan } => {
                    if let Some(track) = self.tracks.get_mut(track_id) {
                        track.pan = pan.clamp(0.0, 1.0);
                    }
                }
                SetTrackStartFrame {
                    track_id,
                    start_frame,
                } => {
                    if let Some(track) = self.tracks.get_mut(track_id) {
                        track.start_frame = start_frame.max(0);
                    }
                }
                MuteTrack { track_id, muted } => {
                    if let Some(track) = self.tracks.get_mut(track_id) {
                        track.muted = muted;
                    }
                }
                SoloTrack { track_id, solo } => {
                    if let Some(track) = self.tracks.get_mut(track_id) {
                        track.solo = solo;
                    }
                }
                AddTrack { player_ptr } => {
                    // SAFETY: This pointer was created in `DAWEngine::load_track` via
                    // `Box::into_raw`. It is sent through the SPSC queue exactly once and
                    // consumed exactly once here. No aliasing is possible because the
                    // control thread no longer holds the raw pointer after pushing the cmd.
                    let player = unsafe { Box::from_raw(player_ptr as *mut TrackPlayer) };
                    if let Err(player) = self.tracks.add(player) {
                        self.retire_track(player);
                    }
                }
                RemoveTrack { track_id } => {
                    if let Some(player) = self.tracks.remove(track_id) {
                        self.retire_track(player);
                    }
                }
                RestartTrack {
                    track_id,
                    player_ptr,
                } => {
                    // SAFETY: the control thread transfers this allocation exactly once.
                    // Both rejected replacements and old players leave on the retirement queue.
                    let player = unsafe { Box::from_raw(player_ptr as *mut TrackPlayer) };
                    if let Some(old) = self.tracks.remove(track_id) {
                        self.retire_track(old);
                        if let Err(player) = self.tracks.add(player) {
                            self.retire_track(player);
                        }
                    } else {
                        self.retire_track(player);
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Main real-time processing entry point
    // ─────────────────────────────────────────────────────────────────────

    /// Processes one hardware callback block (interleaved stereo f32).
    ///
    /// # Real-Time Safety
    /// Zero heap allocations. Zero blocking operations. Zero OS locks.
    pub fn process_interleaved(&mut self, output: &mut [f32], channels: usize) {
        self.process_samples(output, channels);
    }

    /// Render every frame in bounded scratch-sized chunks, converting to the
    /// hardware's actual sample format without a callback allocation.
    pub fn process_samples<T: cpal::Sample + cpal::FromSample<f32>>(
        &mut self,
        output: &mut [T],
        channels: usize,
    ) {
        output.fill(T::EQUILIBRIUM);
        if channels == 0 {
            return;
        }
        self.handle_commands();
        for chunk in output.chunks_mut(Self::MAX_BLOCK_FRAMES * channels) {
            self.process_chunk(chunk, channels);
        }
    }

    fn process_chunk<T: cpal::Sample + cpal::FromSample<f32>>(
        &mut self,
        output: &mut [T],
        channels: usize,
    ) {
        // A malformed/unsupported channel count must never cause division by
        // zero. Keep the callback allocation-free while guaranteeing silence.
        if channels == 0 {
            output.fill(T::EQUILIBRIUM);
            return;
        }

        // 1. Process a bounded number of pending UI commands.

        let frames = output.len() / channels;
        let meter_frames = frames.min(Self::MAX_BLOCK_FRAMES);

        // 2. Clear scratch mix bus
        for i in 0..meter_frames {
            self.scratch_left[i] = 0.0;
            self.scratch_right[i] = 0.0;
        }

        // 3. Mix all active tracks into the scratch bus
        if self.is_playing {
            let solo_active = self.tracks.has_solo();
            let playhead_frame = self.playhead_frame;
            self.tracks.iter_mut().for_each(|track| {
                track.mix_into(
                    &mut self.scratch_left[..meter_frames],
                    &mut self.scratch_right[..meter_frames],
                    meter_frames,
                    &mut self.retired_blocks,
                    solo_active,
                    playhead_frame,
                );
            });
        }

        // 4. Add optional test tone
        if self.is_playing && self.test_tone_enabled {
            for i in 0..meter_frames {
                let s = self.oscillator.next_sample() * 0.15; // quiet reference level
                self.scratch_left[i] += s;
                self.scratch_right[i] += s;
            }
        }

        // 5. Apply master gain (with de-zippering) and write to hardware buffer
        for f in 0..frames {
            if self.is_playing {
                // Clock lives on the audio thread; UI refresh rate cannot change timing.
                let previous = self.beat_phase;
                self.beat_phase += self.bpm as f64 / (60.0 * self.sample_rate as f64);
                if (previous == 0.0 || previous.floor() != self.beat_phase.floor())
                    && self.metronome
                {
                    self.click_remaining = (self.sample_rate * 0.025) as usize;
                }
                if self.sequence
                    && (previous == 0.0
                        || (previous * 2.0).floor() != (self.beat_phase * 2.0).floor())
                {
                    const NOTES: [u8; 16] = [
                        50, 57, 60, 57, 53, 60, 65, 60, 48, 55, 60, 62, 45, 52, 57, 64,
                    ];
                    if let Some(note) = self.sequence_note.take() {
                        self.synth.note_off(note);
                    }
                    let note = NOTES[(self.beat_phase * 2.0) as usize % NOTES.len()];
                    self.synth.note_on(note, 0.72);
                    self.sequence_note = Some(note);
                }
            }
            let synth = self.synth.next_frame();
            self.scratch_left[f] += synth[0];
            self.scratch_right[f] += synth[1];
            if self.is_playing && self.metronome && self.click_remaining > 0 {
                let time = self.click_remaining as f32 / self.sample_rate;
                let click = (time * 1500.0 * std::f32::consts::TAU).sin() * time * 3.0;
                self.scratch_left[f] += click;
                self.scratch_right[f] += click;
                self.click_remaining -= 1;
            }
            let gain = self.master_gain.next_gain();
            let l = if f < meter_frames {
                self.scratch_left[f] * gain
            } else {
                0.0
            };
            let r = if f < meter_frames {
                self.scratch_right[f] * gain
            } else {
                0.0
            };

            if channels >= 2 {
                output[f * channels] = T::from_sample(l.clamp(-1.0, 1.0));
                output[f * channels + 1] = T::from_sample(r.clamp(-1.0, 1.0));
                // Explicitly clear channels beyond stereo instead of leaving
                // stale/uninitialized samples in the hardware output buffer.
                for channel in 2..channels {
                    output[f * channels + channel] = T::EQUILIBRIUM;
                }
            } else {
                output[f * channels] = T::from_sample(((l + r) * 0.5).clamp(-1.0, 1.0));
            }

            // Store final mixed signal back into scratch for metering
            if f < meter_frames {
                self.scratch_left[f] = l;
                self.scratch_right[f] = r;
            }
        }

        if self.is_playing {
            self.playhead_frame += frames as i64;
        }

        // 6. Compute meters
        let (peak_l, peak_r, rms_l, rms_r) = self.meter.process_block(
            &self.scratch_left[..meter_frames],
            &self.scratch_right[..meter_frames],
        );

        // 7. Push telemetry (lossy – drop if queue is full)
        let _ = self.telemetry_producer.push(TelemetryFrame {
            peak_left: peak_l,
            peak_right: peak_r,
            rms_left: rms_l,
            rms_right: rms_r,
            playhead_frame: self.playhead_frame,
            total_duration_frames: self.tracks.timeline_duration(),
            is_playing: self.is_playing,
            device_error_flag: 0,
        });
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ringbuf::{create_engine_queues, create_stream_queue, DecodedBlock, TrackId};
    use crate::track::TrackPlayer;

    /// Unsupported/multichannel device layouts must never leak stale buffer data.
    /// This exercises the real callback with an active signal, not just silence.
    #[test]
    fn multichannel_output_clears_channels_beyond_stereo_while_playing() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48_000.0, audio);
        ui.cmd_producer
            .push(EngineCommand::SetTestTone {
                enabled: true,
                frequency_hz: 440.0,
            })
            .unwrap();
        ui.cmd_producer.push(EngineCommand::Play).unwrap();

        let mut output = vec![1.0f32; 128 * 6];
        processor.process_interleaved(&mut output, 6);
        assert!(output
            .as_chunks::<6>()
            .0
            .iter()
            .any(|frame| frame[0] != 0.0));
        for frame in output.as_chunks::<6>().0 {
            assert_eq!(&frame[2..], &[0.0; 4]);
        }
    }

    /// If the backend unexpectedly supplies a larger block than the preallocated
    /// scratch capacity, the unprocessed tail must be deterministically silent.
    #[test]
    fn oversized_callback_renders_output_tail() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48_000.0, audio);
        ui.cmd_producer
            .push(EngineCommand::SetTestTone {
                enabled: true,
                frequency_hz: 440.0,
            })
            .unwrap();
        ui.cmd_producer.push(EngineCommand::Play).unwrap();

        let frames = AudioProcessor::MAX_BLOCK_FRAMES + 19;
        let mut output = vec![1.0f32; frames * 2];
        processor.process_interleaved(&mut output, 2);
        assert!(output[..AudioProcessor::MAX_BLOCK_FRAMES * 2]
            .iter()
            .any(|sample| *sample != 0.0));
        assert!(output[AudioProcessor::MAX_BLOCK_FRAMES * 2..]
            .iter()
            .any(|sample| *sample != 0.0));
    }

    #[test]
    fn test_silence_when_stopped() {
        let (_, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48000.0, audio);
        let mut buffer = vec![0.0f32; 256];
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn zero_channel_count_clears_output_without_panicking() {
        let (_, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48000.0, audio);
        let mut buffer = vec![1.0f32; 16];

        processor.process_interleaved(&mut buffer, 0);

        assert!(buffer.iter().all(|&sample| sample == 0.0));
    }

    #[test]
    fn extra_output_channels_are_cleared() {
        let (_, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48000.0, audio);
        // Four channels per frame; initialize all channels to non-silence.
        let mut buffer = vec![1.0f32; 4 * 16];

        processor.process_interleaved(&mut buffer, 4);

        for frame in buffer.as_chunks::<4>().0 {
            assert_eq!(frame[2], 0.0);
            assert_eq!(frame[3], 0.0);
        }
    }

    #[test]
    fn test_test_tone_when_playing() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48000.0, audio);

        ui.cmd_producer.push(EngineCommand::Play).unwrap();
        ui.cmd_producer
            .push(EngineCommand::SetTestTone {
                enabled: true,
                frequency_hz: 440.0,
            })
            .unwrap();

        let mut buffer = vec![0.0f32; 256];
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().any(|&s| s != 0.0));
    }

    #[test]
    fn test_audio_processor_playback_and_metering() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48000.0, audio);
        let mut buffer = vec![0.0f32; 256];

        // Initially stopped: silence
        processor.process_interleaved(&mut buffer, 2);
        assert_eq!(buffer[0], 0.0);
        let frame1 = ui.telemetry_consumer.pop().unwrap();
        assert!(!frame1.is_playing);

        // Enable test tone and play
        ui.cmd_producer
            .push(EngineCommand::SetTestTone {
                enabled: true,
                frequency_hz: 440.0,
            })
            .unwrap();
        ui.cmd_producer.push(EngineCommand::Play).unwrap();
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().any(|&s| s != 0.0));

        let frame2 = ui.telemetry_consumer.pop().unwrap();
        assert!(frame2.is_playing);
        assert!(frame2.peak_left > 0.0);
    }

    /// Pause must silence output without rewinding; Play must resume from the current
    /// transport position. This tests the callback command path, not a hardware device.
    #[test]
    fn pause_silences_and_play_resumes_transport() {
        let (mut ui, audio) = create_engine_queues(32, 32);
        let mut processor = AudioProcessor::new(48000.0, audio);
        let mut buffer = vec![0.0f32; 256];

        ui.cmd_producer
            .push(EngineCommand::SetTestTone {
                enabled: true,
                frequency_hz: 440.0,
            })
            .unwrap();
        ui.cmd_producer.push(EngineCommand::Play).unwrap();
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().any(|sample| *sample != 0.0));
        let playing = ui.telemetry_consumer.pop().unwrap();
        assert!(playing.is_playing);
        let playhead_before_pause = playing.playhead_frame;
        assert!(playhead_before_pause > 0);

        ui.cmd_producer.push(EngineCommand::Pause).unwrap();
        buffer.fill(1.0);
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().all(|sample| *sample == 0.0));
        let paused = ui.telemetry_consumer.pop().unwrap();
        assert!(!paused.is_playing);
        assert_eq!(paused.playhead_frame, playhead_before_pause);

        ui.cmd_producer.push(EngineCommand::Play).unwrap();
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().any(|sample| *sample != 0.0));
        let resumed = ui.telemetry_consumer.pop().unwrap();
        assert!(resumed.is_playing);
        assert!(resumed.playhead_frame > playhead_before_pause);
    }

    #[test]
    fn test_track_audio_plays_through_mixer() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48000.0, audio);

        // Create a fake track with known audio data
        let (producer, consumer) = create_stream_queue(8);
        let mut block = DecodedBlock::silent(128);
        for i in 0..128 {
            block.samples[i * 2] = 0.5;
            block.samples[i * 2 + 1] = 0.5;
        }
        block.is_last = true;
        let _ = {
            let mut prod = producer;
            prod.push(block).unwrap();
            prod
        };

        let track = TrackPlayer::new(TrackId(1), consumer, 1.0, 128);
        assert!(processor.tracks_mut().add(Box::new(track)).is_ok());

        ui.cmd_producer.push(EngineCommand::Play).unwrap();
        let mut buffer = vec![0.0f32; 256];
        processor.process_interleaved(&mut buffer, 2);

        assert!(buffer.iter().any(|&s| s != 0.0));
    }

    #[test]
    fn hypnosynth_note_event_reaches_the_output_without_transport_play() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48_000.0, audio);
        ui.cmd_producer
            .push(EngineCommand::SynthEvent {
                event: 0,
                key: 60,
                value: 0.8,
            })
            .unwrap();
        let mut output = vec![0.0f32; 1024 * 2];
        processor.process_interleaved(&mut output, 2);
        assert!(output.iter().any(|sample| sample.abs() > 0.0001));
    }

    #[test]
    fn solo_mutes_other_tracks_in_the_mixer() {
        let (mut ui, audio) = create_engine_queues(16, 16);
        let mut processor = AudioProcessor::new(48_000.0, audio);
        for id in [1, 2] {
            let (mut producer, consumer) = create_stream_queue(2);
            let mut block = DecodedBlock::silent(128);
            let value = if id == 1 { 0.2 } else { 0.4 };
            for frame in 0..128 {
                block.samples[frame * 2] = value;
                block.samples[frame * 2 + 1] = value;
            }
            producer.push(block).unwrap();
            let mut player = TrackPlayer::new(TrackId(id), consumer, 1.0, 128);
            player.solo = id == 1;
            assert!(processor.tracks_mut().add(Box::new(player)).is_ok());
        }

        ui.cmd_producer.push(EngineCommand::Play).unwrap();
        let mut output = vec![0.0f32; 256];
        processor.process_interleaved(&mut output, 2);
        assert!(output.iter().any(|sample| *sample != 0.0));
        assert!(output.iter().all(|sample| *sample < 0.2));
    }

    /// Regression for issue #5: Stop must silence output and reset playhead.
    ///
    /// Sequence:
    /// 1. Install a track with non-silent audio.
    /// 2. Play → output is non-silent, telemetry reports playing.
    /// 3. Stop → subsequent process blocks are silent, playhead is 0, is_playing false.
    #[test]
    fn stop_silences_output_and_resets_playhead() {
        let (mut ui, audio) = create_engine_queues(32, 32);
        let mut processor = AudioProcessor::new(48000.0, audio);

        // Install a track with continuous non-silent data (not marked last so it keeps playing)
        let (mut producer, consumer) = create_stream_queue(16);
        for _ in 0..4 {
            let mut block = DecodedBlock::silent(128);
            for i in 0..128 {
                block.samples[i * 2] = 0.4;
                block.samples[i * 2 + 1] = 0.4;
            }
            producer.push(block).unwrap();
        }

        let track = TrackPlayer::new(TrackId(42), consumer, 1.0, 512);
        assert!(processor.tracks_mut().add(Box::new(track)).is_ok());

        // Play
        ui.cmd_producer.push(EngineCommand::Play).unwrap();
        let mut buffer = vec![0.0f32; 256];
        processor.process_interleaved(&mut buffer, 2);
        assert!(buffer.iter().any(|&s| s != 0.0), "Play must produce audio");

        let frame_play = ui.telemetry_consumer.pop().unwrap();
        assert!(frame_play.is_playing);
        assert!(frame_play.playhead_frame > 0);

        // Stop
        ui.cmd_producer.push(EngineCommand::Stop).unwrap();
        // Process several blocks after Stop — all must be silent
        for _ in 0..4 {
            buffer.fill(1.0); // poison so we can detect silence write
            processor.process_interleaved(&mut buffer, 2);
            assert!(
                buffer.iter().all(|&s| s == 0.0),
                "Stop must produce silence on subsequent callbacks"
            );
        }

        // Drain telemetry and check the latest frame
        let mut last = None;
        while let Ok(f) = ui.telemetry_consumer.pop() {
            last = Some(f);
        }
        let frame_stop = last.expect("expected telemetry after Stop");
        assert!(!frame_stop.is_playing, "telemetry must report stopped");
        assert_eq!(frame_stop.playhead_frame, 0, "playhead must reset to zero");
    }
}

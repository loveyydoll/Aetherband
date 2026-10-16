//! Per-track audio player running inside the real-time audio thread.
//!
//! Reads pre-decoded stereo blocks from the lock-free SPSC ring buffer
//! produced by the background `StreamDecoder` worker.
//!
//! # Real-Time Safety
//! This module contains **zero** heap allocations, **zero** OS locks, and
//! **zero** filesystem access. All buffers are pre-allocated at construction.

use crate::dsp::GainRamp;
use crate::ringbuf::{DecodedBlock, TrackId};
use rtrb::Consumer;
use std::f32::consts::PI;

/// State of a single audio track inside the real-time audio thread.
pub struct TrackPlayer {
    /// Stable ID for this track.
    pub id: TrackId,
    /// Consumer side of the disk-stream ring buffer.
    stream_consumer: Consumer<DecodedBlock>,
    /// Current block being consumed (pre-allocated slot).
    current_block: Option<DecodedBlock>,
    /// Read cursor within `current_block` (in stereo frames).
    block_cursor: usize,
    /// Per-track volume (de-zippering).
    pub gain: GainRamp,
    /// Pan position [0.0 = full left … 0.5 = centre … 1.0 = full right].
    pub pan: f32,
    /// Whether this track is muted.
    pub muted: bool,
    /// Whether this track has reached end-of-file.
    pub finished: bool,
    /// Total duration in output-rate frames (for UI scrubber).
    pub total_frames: i64,
}

impl TrackPlayer {
    /// Creates a new track player.
    ///
    /// `stream_consumer` is the consumer end of the ring buffer filled by `StreamDecoder`.
    pub fn new(
        id: TrackId,
        stream_consumer: Consumer<DecodedBlock>,
        initial_gain: f32,
        total_frames: i64,
    ) -> Self {
        Self {
            id,
            stream_consumer,
            current_block: None,
            block_cursor: 0,
            gain: GainRamp::new(initial_gain),
            pan: 0.5,
            muted: false,
            finished: false,
            total_frames,
        }
    }

    /// Fills `out_left` and `out_right` with the next `frames` samples.
    ///
    /// Adds (mixes) into the output buffers rather than overwriting them,
    /// so multiple tracks can mix into the same bus.
    ///
    /// # Real-Time Safety
    /// Zero allocations. Blocks on nothing; if the ring buffer is empty
    /// (decoder hasn't caught up) we output silence for the missing frames.
    #[inline]
    pub fn mix_into(&mut self, out_left: &mut [f32], out_right: &mut [f32], frames: usize) {
        if self.muted || self.finished {
            return;
        }

        // Equal-Power panning law
        let pan_angle = self.pan * (PI / 2.0);
        let pan_l = pan_angle.cos();
        let pan_r = pan_angle.sin();

        let mut written = 0;

        while written < frames {
            // Ensure we have a current block
            if self.current_block.is_none() || self.block_cursor >= self.current_block.as_ref().unwrap().valid_frames {
                match self.stream_consumer.pop() {
                    Ok(block) => {
                        let is_last = block.is_last;
                        self.current_block = Some(block);
                        self.block_cursor = 0;
                        if is_last {
                            // We'll still drain this block, then mark finished after
                        }
                    }
                    Err(_) => {
                        // Ring buffer empty - decoder hasn't caught up, output silence
                        // for remaining frames this callback block
                        break;
                    }
                }
            }

            let block = match &self.current_block {
                Some(b) => b,
                None => break,
            };

            let remaining_in_block = block.valid_frames - self.block_cursor;
            let to_copy = remaining_in_block.min(frames - written);

            for i in 0..to_copy {
                let frame_idx = (self.block_cursor + i) * 2;
                let sample_l = block.samples[frame_idx];
                let sample_r = block.samples[frame_idx + 1];
                let gain = self.gain.next_gain();

                out_left[written + i] += sample_l * gain * pan_l;
                out_right[written + i] += sample_r * gain * pan_r;
            }

            self.block_cursor += to_copy;
            written += to_copy;

            // Check if this block was the last and we've exhausted it
            if let Some(block) = &self.current_block {
                if block.is_last && self.block_cursor >= block.valid_frames {
                    self.finished = true;
                    break;
                }
            }
        }
    }

    /// Resets playback to the beginning (used on Stop or Seek).
    ///
    /// Drains the ring buffer so the decoder worker can refill from
    /// the new position.
    pub fn reset(&mut self) {
        // Drain all pending blocks (non-blocking)
        while self.stream_consumer.pop().is_ok() {}
        self.current_block = None;
        self.block_cursor = 0;
        self.finished = false;
    }
}

/// Maximum number of simultaneous tracks the audio thread supports.
/// Kept fixed to avoid heap allocation at runtime.
pub const MAX_TRACKS: usize = 64;

/// Fixed-size array of track players managed by the audio thread.
///
/// Using a fixed-size array avoids any dynamic allocation on the audio thread.
pub struct TrackSlots {
    slots: [Option<Box<TrackPlayer>>; MAX_TRACKS],
    count: usize,
}

impl TrackSlots {
    /// Creates an empty set of track slots.
    pub fn new() -> Self {
        // SAFETY: Option<TrackPlayer> is None-initialisable.
        // We can't use [None; MAX_TRACKS] because TrackPlayer is not Copy.
        Self {
            slots: std::array::from_fn(|_| None),
            count: 0,
        }
    }

    /// Returns the number of currently active tracks.
    pub fn count(&self) -> usize {
        self.count
    }

    /// Adds a track. Returns `false` if the slot table is full.
    pub fn add(&mut self, player: Box<TrackPlayer>) -> Result<(), Box<TrackPlayer>> {
        for slot in self.slots.iter_mut() {
            if slot.is_none() {
                *slot = Some(player);
                self.count += 1;
                return Ok(());
            }
        }
        Err(player)
    }

    /// Removes a track by ID and returns ownership for deferred control-thread destruction.
    pub fn remove(&mut self, id: TrackId) -> Option<Box<TrackPlayer>> {
        for slot in self.slots.iter_mut() {
            if matches!(slot, Some(p) if p.id == id) {
                self.count -= 1;
                return slot.take();
            }
        }
        None
    }

    /// Returns a mutable reference to a track slot by ID.
    pub fn get_mut(&mut self, id: TrackId) -> Option<&mut TrackPlayer> {
        self.slots.iter_mut().find_map(|s| s.as_deref_mut().filter(|p| p.id == id))
    }

    /// Iterates mutably over all active track players.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = &mut TrackPlayer> {
        self.slots.iter_mut().filter_map(|s| s.as_deref_mut())
    }

    /// Resets all tracks (Stop / Seek operations).
    pub fn reset_all(&mut self) {
        for slot in self.slots.iter_mut() {
            if let Some(p) = slot.as_deref_mut() { p.reset(); }
        }
    }

    /// Returns the longest `total_frames` across all tracks (timeline duration).
    pub fn timeline_duration(&self) -> i64 {
        self.slots.iter()
            .filter_map(|s| s.as_ref())
            .map(|p| p.total_frames)
            .max()
            .unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ringbuf::create_stream_queue;

    fn make_track(id: u32, frames: usize) -> (TrackPlayer, rtrb::Producer<DecodedBlock>) {
        let (producer, consumer) = create_stream_queue(8);
        (TrackPlayer::new(TrackId(id), consumer, 1.0, frames as i64), producer)
    }

    #[test]
    fn test_track_slots_add_and_remove() {
        let mut slots = TrackSlots::new();
        let (p1, _prod1) = make_track(1, 48000);
        let (p2, _prod2) = make_track(2, 48000);

        assert!(slots.add(Box::new(p1)).is_ok());
        assert!(slots.add(Box::new(p2)).is_ok());
        assert_eq!(slots.count(), 2);

        assert!(slots.remove(TrackId(1)).is_some());
        assert_eq!(slots.count(), 1);
        assert!(slots.remove(TrackId(99)).is_none()); // non-existent
    }

    #[test]
    fn test_track_silence_on_empty_buffer() {
        let (mut player, _prod) = make_track(1, 1024);
        let mut left = vec![0.0f32; 128];
        let mut right = vec![0.0f32; 128];
        // No blocks in buffer → output remains silence
        player.mix_into(&mut left, &mut right, 128);
        assert!(left.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn test_track_plays_block_data() {
        let (mut player, mut prod) = make_track(1, 512);

        // Push a block of known values
        let mut block = DecodedBlock::silent(128);
        for i in 0..128 {
            block.samples[i * 2] = 0.5;     // Left
            block.samples[i * 2 + 1] = 0.5; // Right
        }
        block.is_last = true;
        prod.push(block).unwrap();

        let mut left = vec![0.0f32; 128];
        let mut right = vec![0.0f32; 128];
        player.mix_into(&mut left, &mut right, 128);

        // All samples should be non-zero (panning + gain applied)
        assert!(left.iter().any(|&s| s > 0.0));
        assert!(right.iter().any(|&s| s > 0.0));
    }
}

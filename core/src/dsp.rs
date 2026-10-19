//! DSP primitives: oscillators, parameter smoothing, and metering.
//!
//! All algorithms are allocation-free, lock-free, and safe for real-time threads.

use std::f32::consts::PI;

/// A pure Sine Wave oscillator for audio test tones and signal generation.
#[derive(Debug, Clone)]
pub struct SineOscillator {
    sample_rate: f32,
    frequency_hz: f32,
    phase: f32,
    phase_increment: f32,
}

impl SineOscillator {
    /// Creates a new sine oscillator at the given sample rate and frequency.
    pub fn new(sample_rate: f32, frequency_hz: f32) -> Self {
        let phase_increment = (2.0 * PI * frequency_hz) / sample_rate;
        Self {
            sample_rate,
            frequency_hz,
            phase: 0.0,
            phase_increment,
        }
    }

    /// Sets a new oscillator frequency.
    pub fn set_frequency(&mut self, frequency_hz: f32) {
        self.frequency_hz = frequency_hz;
        self.phase_increment = (2.0 * PI * frequency_hz) / self.sample_rate;
    }

    /// Updates the sample rate.
    pub fn set_sample_rate(&mut self, sample_rate: f32) {
        self.sample_rate = sample_rate;
        self.phase_increment = (2.0 * PI * self.frequency_hz) / sample_rate;
    }

    /// Generates the next audio sample in the range [-1.0, 1.0].
    #[inline]
    pub fn next_sample(&mut self) -> f32 {
        let sample = self.phase.sin();
        self.phase += self.phase_increment;
        if self.phase >= 2.0 * PI {
            self.phase -= 2.0 * PI;
        }
        sample
    }

    /// Resets the phase to 0.
    pub fn reset(&mut self) {
        self.phase = 0.0;
    }
}

/// An anti-zipper linear gain ramp for smooth volume adjustments.
///
/// Prevents high-frequency stepping clicks when users adjust volume faders.
#[derive(Debug, Clone)]
pub struct GainRamp {
    current_gain: f32,
    target_gain: f32,
    step: f32,
    remaining_frames: usize,
}

impl GainRamp {
    /// Creates a gain ramp initialized to an initial gain value.
    pub fn new(initial_gain: f32) -> Self {
        Self {
            current_gain: initial_gain,
            target_gain: initial_gain,
            step: 0.0,
            remaining_frames: 0,
        }
    }

    /// Targets a new gain value smoothly over `ramp_frames` audio samples.
    pub fn set_target(&mut self, target_gain: f32, ramp_frames: usize) {
        self.target_gain = target_gain;
        if ramp_frames == 0 {
            self.current_gain = target_gain;
            self.remaining_frames = 0;
            self.step = 0.0;
        } else {
            self.remaining_frames = ramp_frames;
            self.step = (target_gain - self.current_gain) / (ramp_frames as f32);
        }
    }

    /// Advances and returns the current interpolated gain factor.
    #[inline]
    pub fn next_gain(&mut self) -> f32 {
        if self.remaining_frames > 0 {
            self.current_gain += self.step;
            self.remaining_frames -= 1;
            if self.remaining_frames == 0 {
                self.current_gain = self.target_gain;
                self.step = 0.0;
            }
        }
        self.current_gain
    }

    /// Returns the current gain level without advancing.
    #[inline]
    pub fn current_gain(&self) -> f32 {
        self.current_gain
    }
}

/// Real-time Peak and RMS audio level detector.
#[derive(Debug, Clone, Default)]
pub struct LevelMeter {
    peak_left: f32,
    peak_right: f32,
    sum_squares_left: f32,
    sum_squares_right: f32,
    sample_count: usize,
}

impl LevelMeter {
    /// Creates a new level meter detector.
    pub fn new() -> Self {
        Self::default()
    }

    /// Analyzes an audio buffer block and computes (Peak Left, Peak Right, RMS Left, RMS Right).
    pub fn process_block(&mut self, left: &[f32], right: &[f32]) -> (f32, f32, f32, f32) {
        let len = left.len().min(right.len());
        if len == 0 {
            return (0.0, 0.0, 0.0, 0.0);
        }

        self.peak_left = 0.0;
        self.peak_right = 0.0;
        self.sum_squares_left = 0.0;
        self.sum_squares_right = 0.0;
        self.sample_count = len;

        for i in 0..len {
            let sl = left[i];
            let sr = right[i];

            let abs_l = sl.abs();
            let abs_r = sr.abs();

            if abs_l > self.peak_left {
                self.peak_left = abs_l;
            }
            if abs_r > self.peak_right {
                self.peak_right = abs_r;
            }

            self.sum_squares_left += sl * sl;
            self.sum_squares_right += sr * sr;
        }

        let rms_left = (self.sum_squares_left / (len as f32)).sqrt();
        let rms_right = (self.sum_squares_right / (len as f32)).sqrt();

        (self.peak_left, self.peak_right, rms_left, rms_right)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sine_oscillator_output_bounds() {
        let mut osc = SineOscillator::new(48000.0, 440.0);
        for _ in 0..48000 {
            let sample = osc.next_sample();
            assert!((-1.0..=1.0).contains(&sample));
        }
    }

    #[test]
    fn test_gain_ramp_interpolation() {
        let mut ramp = GainRamp::new(0.0);
        ramp.set_target(1.0, 100);

        for _ in 0..50 {
            ramp.next_gain();
        }
        // At 50 frames, gain should be approx 0.5
        let mid = ramp.current_gain();
        assert!((mid - 0.5).abs() < 0.02);

        for _ in 0..50 {
            ramp.next_gain();
        }
        // At 100 frames, gain should be exactly 1.0
        assert_eq!(ramp.current_gain(), 1.0);
    }

    #[test]
    fn test_level_meter_accuracy() {
        let mut meter = LevelMeter::new();
        let left = vec![1.0, -1.0, 1.0, -1.0];
        let right = vec![0.5, -0.5, 0.5, -0.5];

        let (peak_l, peak_r, rms_l, rms_r) = meter.process_block(&left, &right);
        assert_eq!(peak_l, 1.0);
        assert_eq!(peak_r, 0.5);
        assert!((rms_l - 1.0).abs() < 1e-6);
        assert!((rms_r - 0.5).abs() < 1e-6);
    }
}

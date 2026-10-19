//! Original polyphonic subtractive instrument. All voices and delay storage
//! are allocated before the hardware stream starts; rendering never allocates.
use crate::envelope::{Adsr, AdsrRates, Stage};
use std::f32::consts::TAU;

const VOICES: usize = 16;

/// Original 16-step HypnoSynth phrase. `None` represents a rest when edited.
pub const DEFAULT_SEQUENCE: [Option<u8>; 16] = [
    Some(50),
    Some(57),
    Some(60),
    Some(57),
    Some(53),
    Some(60),
    Some(65),
    Some(60),
    Some(48),
    Some(55),
    Some(60),
    Some(62),
    Some(45),
    Some(52),
    Some(57),
    Some(64),
];

#[derive(Clone, Copy)]
struct Voice {
    note: u8,
    active: bool,
    held: bool,
    phase: [f32; 2],
    envelope: Adsr,
    velocity: f32,
    filter: f32,
    age: u64,
}

impl Default for Voice {
    fn default() -> Self {
        Self {
            note: 60,
            active: false,
            held: false,
            phase: [0.0; 2],
            envelope: Adsr::new(),
            velocity: 0.0,
            filter: 0.0,
            age: 0,
        }
    }
}

pub struct HypnoSynth {
    sample_rate: f32,
    voices: [Voice; VOICES],
    age: u64,
    tone: f32,
    motion: f32,
    space: f32,
    drift: f32,
    gain: f32,
    envelope_rates: AdsrRates,
    pulse: bool,
    lfo: f32,
    delay: Vec<[f32; 2]>,
    delay_cursor: usize,
}

impl HypnoSynth {
    pub fn new(sample_rate: f32) -> Self {
        let sample_rate = sample_rate.clamp(8000.0, 384000.0);
        let mut synth = Self {
            sample_rate,
            voices: [Voice::default(); VOICES],
            age: 0,
            tone: 0.45,
            motion: 0.35,
            space: 0.5,
            drift: 0.3,
            gain: 0.7,
            envelope_rates: AdsrRates::new(40.0, 250.0, 0.72, 500.0, sample_rate),
            pulse: false,
            lfo: 0.0,
            delay: vec![[0.0; 2]; (sample_rate * 0.7) as usize],
            delay_cursor: 0,
        };
        synth.preset(0);
        synth
    }

    /// 0: Morning Haze, 1: Nervous Current, 2: Submerged.
    pub fn preset(&mut self, preset: u8) {
        let values = match preset {
            1 => (0.68, 0.65, 0.28, 0.22, 0.006, 0.18, true),
            2 => (0.18, 0.18, 0.18, 0.12, 0.012, 0.24, false),
            _ => (0.42, 0.38, 0.55, 0.36, 0.06, 0.65, false),
        };
        let attack;
        let release;
        (
            self.tone,
            self.motion,
            self.space,
            self.drift,
            attack,
            release,
            self.pulse,
        ) = values;
        self.envelope_rates = AdsrRates::new(
            attack * 1000.0,
            250.0,
            0.72,
            release * 1000.0,
            self.sample_rate,
        );
    }

    /// Tone, Motion, Space, Drift and Level, normalized to [0, 1].
    pub fn parameter(&mut self, index: u8, value: f32) {
        if !value.is_finite() {
            return;
        }
        let value = value.clamp(0.0, 1.0);
        match index {
            0 => self.tone = value,
            1 => self.motion = value,
            2 => self.space = value,
            3 => self.drift = value,
            4 => self.gain = value,
            _ => (),
        }
    }

    pub fn note_on(&mut self, note: u8, velocity: f32) {
        if note > 127 || !velocity.is_finite() {
            return;
        }
        if velocity <= 0.0 {
            self.note_off(note);
            return;
        }
        self.age = self.age.wrapping_add(1);
        let index = self
            .voices
            .iter()
            .position(|v| v.active && v.note == note)
            .or_else(|| self.voices.iter().position(|v| !v.active))
            .unwrap_or_else(|| {
                self.voices
                    .iter()
                    .enumerate()
                    .min_by_key(|(_, v)| v.age)
                    .map_or(0, |(i, _)| i)
            });
        self.voices[index] = Voice {
            note,
            held: true,
            active: true,
            velocity: velocity.clamp(0.0, 1.0),
            age: self.age,
            ..Voice::default()
        };
        self.voices[index].envelope.gate_on();
    }

    pub fn note_off(&mut self, note: u8) {
        for voice in &mut self.voices {
            if voice.note == note {
                voice.held = false;
                voice.envelope.gate_off();
            }
        }
    }

    pub fn panic(&mut self) {
        self.voices.fill(Voice::default());
        self.delay.fill([0.0; 2]);
    }

    pub fn next_frame(&mut self) -> [f32; 2] {
        self.lfo = (self.lfo + (0.12 + self.motion * 1.8) / self.sample_rate).fract();
        let modulation = (self.lfo * TAU).sin();
        let cutoff = (120.0 * 2.0_f32.powf(self.tone * 6.4 + modulation * self.motion))
            .min(self.sample_rate * 0.35);
        let coefficient = 1.0 - (-TAU * cutoff / self.sample_rate).exp();
        let detune = 2.0_f32.powf((self.drift * 18.0 + modulation * self.drift * 3.0) / 1200.0);
        let mut signal = 0.0;
        for voice in &mut self.voices {
            if !voice.active {
                continue;
            }
            let envelope = voice.envelope.next(&self.envelope_rates);
            if voice.envelope.stage == Stage::Idle {
                voice.active = false;
                continue;
            }
            let frequency = 440.0 * 2.0_f32.powf((voice.note as f32 - 69.0) / 12.0);
            let mut oscillators = 0.0;
            for (index, phase) in voice.phase.iter_mut().enumerate() {
                let increment = (frequency * if index == 0 { 1.0 / detune } else { detune }
                    / self.sample_rate)
                    .min(0.45);
                let mut sample = 2.0 * *phase - 1.0 - poly_blep(*phase, increment);
                if self.pulse {
                    let shifted = (*phase + 0.5 + modulation * 0.08).fract();
                    sample -= 2.0 * shifted - 1.0 - poly_blep(shifted, increment);
                }
                oscillators += sample * 0.5;
                *phase = (*phase + increment).fract();
            }
            voice.filter += coefficient * (oscillators - voice.filter);
            signal += voice.filter * envelope * voice.velocity * 0.09;
        }
        let left_offset = (self.sample_rate * 0.31) as usize;
        let right_offset = (self.sample_rate * 0.47) as usize;
        let length = self.delay.len();
        let left = self.delay[(self.delay_cursor + length - left_offset) % length][0];
        let right = self.delay[(self.delay_cursor + length - right_offset) % length][1];
        self.delay[self.delay_cursor] = [signal + right * 0.42, signal + left * 0.42];
        self.delay_cursor = (self.delay_cursor + 1) % length;
        [
            (signal + left * self.space) * self.gain,
            (signal + right * self.space) * self.gain,
        ]
    }
}

fn poly_blep(phase: f32, step: f32) -> f32 {
    if phase < step {
        let t = phase / step;
        t + t - t * t - 1.0
    } else if phase > 1.0 - step {
        let t = (phase - 1.0) / step;
        t * t + t + t + 1.0
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn presets_sound_release_and_panic_at_supported_rates() {
        for rate in [44100.0, 48000.0, 96000.0] {
            for preset in 0..3 {
                let mut synth = HypnoSynth::new(rate);
                synth.preset(preset);
                for note in [50, 57, 60, 64] {
                    synth.note_on(note, 0.8);
                }
                let mut energy = 0.0;
                for _ in 0..rate as usize {
                    for sample in synth.next_frame() {
                        assert!(sample.is_finite() && sample.abs() < 1.0);
                        energy += sample * sample;
                    }
                }
                assert!(energy > 1.0);
                for note in [50, 57, 60, 64] {
                    synth.note_off(note);
                }
                for _ in 0..(rate as usize * 6) {
                    synth.next_frame();
                }
                assert!(synth.next_frame().iter().all(|s| s.abs() < 0.0001));
                synth.panic();
                assert_eq!(synth.next_frame(), [0.0; 2]);
            }
        }
    }

    #[test]
    fn voice_stealing_and_invalid_parameters_remain_bounded() {
        let mut synth = HypnoSynth::new(48000.0);
        synth.parameter(0, f32::NAN);
        for note in 0..128 {
            synth.note_on(note, 1.0);
        }
        assert_eq!(synth.voices.iter().filter(|v| v.active).count(), VOICES);
        for _ in 0..48000 {
            assert!(synth.next_frame().iter().all(|s| s.is_finite()));
        }
    }
}

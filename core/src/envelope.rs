//! ADSR adapted from SoundCraft by ArtCraft Team and contributors (MIT).
//! Source revision: 2e9ad2f4215bd36e7edf30579e8ce520d5ce67c7.
//! See third_party/soundcraft/LICENSE-MIT and README.md.
const SILENT: f32 = 1.0e-5;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Stage {
    Idle,
    Attack,
    Decay,
    Sustain,
    Release,
}

/// Linear-attack, exponential decay/release ADSR. Times are "to -60 dB" for decay/release.
#[derive(Debug, Clone, Copy)]
pub struct Adsr {
    pub stage: Stage,
    pub level: f32,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct AdsrRates {
    attack: f32,
    decay: f32,
    sustain: f32,
    release: f32,
}

impl AdsrRates {
    pub fn new(a_ms: f32, d_ms: f32, s: f32, r_ms: f32, sr: f32) -> Self {
        let exp60 = |ms: f32| (0.001f32.ln() / (ms * sr * 0.001).max(1.0)).exp();
        Self {
            attack: 1.0 / (a_ms * sr * 0.001).max(1.0),
            decay: exp60(d_ms),
            sustain: s.clamp(0.0, 1.0),
            release: exp60(r_ms),
        }
    }
}

impl Adsr {
    pub const fn new() -> Self {
        Self {
            stage: Stage::Idle,
            level: 0.0,
        }
    }

    pub fn gate_on(&mut self) {
        self.stage = Stage::Attack;
    }

    pub fn gate_off(&mut self) {
        if self.stage != Stage::Idle {
            self.stage = Stage::Release;
        }
    }

    #[inline]
    pub fn next(&mut self, r: &AdsrRates) -> f32 {
        match self.stage {
            Stage::Idle => self.level = 0.0,
            Stage::Attack => {
                self.level += r.attack;
                if self.level >= 1.0 {
                    self.level = 1.0;
                    self.stage = Stage::Decay;
                }
            }
            Stage::Decay => {
                self.level = r.sustain + (self.level - r.sustain) * r.decay;
                if (self.level - r.sustain).abs() < 1e-4 {
                    self.stage = Stage::Sustain;
                }
            }
            Stage::Sustain => self.level = r.sustain,
            Stage::Release => {
                self.level *= r.release;
                if self.level < SILENT {
                    self.level = 0.0;
                    self.stage = Stage::Idle;
                }
            }
        }
        self.level
    }
}

//! Foundational spatial-audio types for Aetherband.
//!
//! This module defines portable channel-layout metadata, normalized source
//! positions, and a small deterministic stereo panning utility. It does not yet
//! render multichannel spatial audio or change the current mixer. Keeping the
//! model independent of the device callback allows the project/session layer
//! and future renderers to adopt spatial concepts first.

/// A named output or bus layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ChannelLayout {
    Mono,
    Stereo,
    Quad,
    Surround51,
    Surround71,
    /// First-order Ambisonics: W, X, Y, Z (four components).
    AmbisonicsFirstOrder,
}

impl ChannelLayout {
    /// Number of discrete channels/components represented by this layout.
    pub const fn channel_count(self) -> usize {
        match self {
            Self::Mono => 1,
            Self::Stereo => 2,
            Self::Quad => 4,
            Self::Surround51 => 6,
            Self::Surround71 => 8,
            Self::AmbisonicsFirstOrder => 4,
        }
    }

    /// True when this layout represents Ambisonic components rather than
    /// loudspeaker feeds. Ambisonic component order/normalization must be
    /// explicitly specified by any encoder/decoder using this layout.
    pub const fn is_ambisonic(self) -> bool {
        matches!(self, Self::AmbisonicsFirstOrder)
    }
}

/// A source position in a right-handed Cartesian coordinate system.
///
/// Axes: +X is right, +Y is forward, +Z is up. Values are relative direction
/// coordinates, not metres. Use normalized() to obtain a unit direction
/// vector. The origin has no defined direction and returns None when normalized.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct SpatialPosition {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl SpatialPosition {
    pub const FRONT: Self = Self { x: 0.0, y: 1.0, z: 0.0 };
    pub const RIGHT: Self = Self { x: 1.0, y: 0.0, z: 0.0 };
    pub const LEFT: Self = Self { x: -1.0, y: 0.0, z: 0.0 };
    pub const ABOVE: Self = Self { x: 0.0, y: 0.0, z: 1.0 };

    /// Creates a direction from Cartesian coordinates.
    pub const fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    /// Returns a finite unit direction, or None for zero/non-finite vectors.
    pub fn normalized(self) -> Option<Self> {
        if !self.x.is_finite() || !self.y.is_finite() || !self.z.is_finite() {
            return None;
        }
        let length_squared = self.x * self.x + self.y * self.y + self.z * self.z;
        if !length_squared.is_finite() || length_squared <= f32::EPSILON {
            return None;
        }
        let inverse_length = length_squared.sqrt().recip();
        Some(Self::new(
            self.x * inverse_length,
            self.y * inverse_length,
            self.z * inverse_length,
        ))
    }

    /// Zero points forward (+Y); positive angles rotate toward the right (+X).
    /// Returns None for a position with no horizontal component.
    pub fn azimuth_radians(self) -> Option<f32> {
        if !self.x.is_finite() || !self.y.is_finite() || (self.x == 0.0 && self.y == 0.0) {
            return None;
        }
        Some(self.x.atan2(self.y))
    }

    /// Returns elevation in radians above the horizontal plane.
    pub fn elevation_radians(self) -> Option<f32> {
        let direction = self.normalized()?;
        Some(direction.z.clamp(-1.0, 1.0).asin())
    }
}

/// Converts a front-hemisphere azimuth into equal-power stereo gains.
///
/// -PI/2 is hard left, 0 is centre, and +PI/2 is hard right. Returns None for
/// non-finite input. Angles outside the front hemisphere are clamped to the
/// nearest edge; this is a simple stereo panning law, not a spatial renderer.
///
/// The returned gains have a squared sum of approximately 1, avoiding the
/// centre dip of linear panning. This function allocates no memory and is
/// suitable as a building block for a future prepared audio graph.
pub fn equal_power_stereo_gains(azimuth_radians: f32) -> Option<(f32, f32)> {
    use std::f32::const::FRAC_PI_2;

    if !azimuth_radians.is_finite() {
        return None;
    }
    let clamped = azimuth_radians.clamp(-FRAC_PI_2, FRAC_PI_2);
    let pan = (clamped + FRAC_PI_2) / std::f32::consts::PI;
    let angle = pan * FRAC_PI_2;
    Some((angle.cos(), angle.sin()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_layouts_report_expected_channel_counts() {
        assert_eq!(ChannelLayout::Mono.channel_count(), 1);
        assert_eq!(ChannelLayout::Stereo.channel_count(), 2);
        assert_eq!(ChannelLayout::Quad.channel_count(), 4);
        assert_eq!(ChannelLayout::Surround51.channel_count(), 6);
        assert_eq!(ChannelLayout::Surround71.channel_count(), 8);
        assert_eq!(ChannelLayout::AmbisonicsFirstOrder.channel_count(), 4);
        assert!(ChannelLayout::AmbisonicsFirstOrder.is_ambisonic());
        assert!(!ChannelLayout::Surround51.is_ambisonic());
    }

    #[test]
    fn normalizes_source_direction() {
        let direction = SpatialPosition::new(3.0, 4.0, 0.0).normalized().unwrap();
        assert!((direction.x - 0.6).abs() < 1e-6);
        assert!((direction.y - 0.8).abs() < 1e-6);
        assert!(direction.z.abs() < 1e-6);
    }

    #[test]
    fn rejects_zero_and_non_finite_directions() {
        assert_eq!(SpatialPosition::default().normalized(), None);
        assert_eq!(SpatialPosition::new(f32::NAN, 1.0, 0.0).normalized(), None);
        assert_eq!(SpatialPosition::default().azimuth_radians(), None);
        assert_eq!(SpatialPosition::default().elevation_radians(), None);
    }

    #[test]
    fn azimuth_uses_front_as_zero_and_right_as_positive() {
        assert!(SpatialPosition::FRONT.azimuth_radians().unwrap().abs() < 1e-6);
        assert!((SpatialPosition::RIGHT.azimuth_radians().unwrap()
            - std::f32::consts::FRAC_PI_2).abs() < 1e-6);
        assert!((SpatialPosition::LEFT.azimuth_radians().unwrap()
            + std::f32::consts::FRAC_PI_2).abs() < 1e-6);
    }

    #[test]
    fn equal_power_pan_has_expected_hard_left_center_and_hard_right() {
        use std::f32::consts::FRAC_PI_2;
        let left = equal_power_stereo_gains(-FRAC_PI_2).unwrap();
        let center = equal_power_stereo_gains(0.0).unwrap();
        let right = equal_power_stereo_gains(FRAC_PI_2).unwrap();
        assert!(left.0.abs() < 1e-6);
        assert!((left.1 - 1.0).abs() < 1e-6);
        assert!((center.0 - std::f32::consts::FRAC_1_SQRT_2).abs() < 1e-6);
        assert!((center.1 - std::f32::consts::FRAC_1_SQRT_2).abs() < 1e-6);
        assert!((right.0 - 1.0).abs() < 1e-6);
        assert!(right.1.abs() < 1e-6);
    }

    #[test]
    fn equal_power_pan_preserves_power_and_rejects_non_finite_input() {
        for angle in [-1.2, -0.5, 0.0, 0.5, 1.2] {
            let (left, right) = equal_power_stereo_gains(angle).unwrap();
            assert!((left * left + right * right - 1.0).abs() < 1e-6);
        }
        assert_eq!(equal_power_stereo_gains(f32::NAN), None);
        assert_eq!(equal_power_stereo_gains(f32::INFINITY), None);
    }
}

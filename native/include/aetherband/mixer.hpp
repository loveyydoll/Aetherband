#pragma once

#include "aetherband/audio_buffer.hpp"

namespace aetherband {

/// Adds source samples into a destination buffer without clipping.
/// Buffers must have identical channel and frame counts.
class Mixer final {
public:
    static void add(const AudioBuffer& source, AudioBuffer& destination, float gain = 1.0F);
};

} // namespace aetherband

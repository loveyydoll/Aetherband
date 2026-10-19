#include "aetherband/mixer.hpp"

#include <stdexcept>

namespace aetherband {

void Mixer::add(const AudioBuffer& source, AudioBuffer& destination, const float gain) {
    if (source.channel_count() != destination.channel_count() ||
        source.frame_count() != destination.frame_count()) {
        throw std::invalid_argument("Mixer buffers must have matching dimensions");
    }

    for (std::size_t channel = 0; channel < source.channel_count(); ++channel) {
        const float* input = source.channel_data(channel);
        float* output = destination.channel_data(channel);
        for (std::size_t frame = 0; frame < source.frame_count(); ++frame) {
            output[frame] += input[frame] * gain;
        }
    }
}

} // namespace aetherband

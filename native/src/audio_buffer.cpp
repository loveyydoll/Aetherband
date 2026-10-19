#include "aetherband/audio_buffer.hpp"

#include <algorithm>
#include <stdexcept>

namespace aetherband {

AudioBuffer::AudioBuffer(const std::size_t channel_count, const std::size_t frame_count) {
    resize(channel_count, frame_count);
}

void AudioBuffer::resize(const std::size_t channel_count, const std::size_t frame_count) {
    channels_.resize(channel_count);
    for (auto& channel : channels_) {
        channel.resize(frame_count, 0.0F);
    }
    frame_count_ = frame_count;
}

void AudioBuffer::clear() noexcept {
    for (auto& channel : channels_) {
        std::fill(channel.begin(), channel.end(), 0.0F);
    }
}

std::size_t AudioBuffer::channel_count() const noexcept {
    return channels_.size();
}

std::size_t AudioBuffer::frame_count() const noexcept {
    return frame_count_;
}

float* AudioBuffer::channel_data(const std::size_t channel) {
    return channels_.at(channel).data();
}

const float* AudioBuffer::channel_data(const std::size_t channel) const {
    return channels_.at(channel).data();
}

float& AudioBuffer::sample(const std::size_t channel, const std::size_t frame) {
    return channels_.at(channel).at(frame);
}

const float& AudioBuffer::sample(const std::size_t channel, const std::size_t frame) const {
    return channels_.at(channel).at(frame);
}

} // namespace aetherband

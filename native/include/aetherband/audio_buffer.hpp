#pragma once

#include <cstddef>
#include <vector>

namespace aetherband {

/// Planar floating-point audio buffer. Channel storage is allocated when the
/// buffer is constructed/resized; do not resize it from a real-time callback.
class AudioBuffer final {
public:
    AudioBuffer() = default;
    AudioBuffer(std::size_t channel_count, std::size_t frame_count);

    void resize(std::size_t channel_count, std::size_t frame_count);
    void clear() noexcept;

    [[nodiscard]] std::size_t channel_count() const noexcept;
    [[nodiscard]] std::size_t frame_count() const noexcept;

    [[nodiscard]] float* channel_data(std::size_t channel);
    [[nodiscard]] const float* channel_data(std::size_t channel) const;

    [[nodiscard]] float& sample(std::size_t channel, std::size_t frame);
    [[nodiscard]] const float& sample(std::size_t channel, std::size_t frame) const;

private:
    std::vector<std::vector<float>> channels_;
    std::size_t frame_count_ = 0;
};

} // namespace aetherband

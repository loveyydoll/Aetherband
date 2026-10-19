#include "aetherband/audio_buffer.hpp"

#include <cstdlib>
#include <iostream>

namespace {
void expect(const bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(EXIT_FAILURE);
    }
}
}

int main() {
    aetherband::AudioBuffer buffer(2, 4);
    expect(buffer.channel_count() == 2, "channel count");
    expect(buffer.frame_count() == 4, "frame count");
    expect(buffer.sample(0, 0) == 0.0F, "new samples initialize to silence");

    buffer.sample(1, 2) = 0.75F;
    buffer.clear();
    expect(buffer.sample(1, 2) == 0.0F, "clear resets samples to silence");

    buffer.resize(1, 3);
    expect(buffer.channel_count() == 1, "resize changes channel count");
    expect(buffer.frame_count() == 3, "resize changes frame count");
    return EXIT_SUCCESS;
}

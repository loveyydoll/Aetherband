#include "aetherband/mixer.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

namespace {
void expect(const bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(EXIT_FAILURE);
    }
}
}

int main() {
    aetherband::AudioBuffer source(2, 3);
    aetherband::AudioBuffer destination(2, 3);

    source.sample(0, 0) = 0.5F;
    source.sample(1, 2) = -0.25F;
    aetherband::Mixer::add(source, destination, 2.0F);

    expect(destination.sample(0, 0) == 1.0F, "gain is applied");
    expect(destination.sample(1, 2) == -0.5F, "negative samples are preserved");

    aetherband::Mixer::add(source, destination);
    expect(destination.sample(0, 0) == 1.5F, "mix accumulates without internal clipping");

    bool threw = false;
    try {
        aetherband::AudioBuffer mismatch(1, 3);
        aetherband::Mixer::add(source, mismatch);
    } catch (const std::invalid_argument&) {
        threw = true;
    }
    expect(threw, "mismatched buffer dimensions are rejected");
    return EXIT_SUCCESS;
}

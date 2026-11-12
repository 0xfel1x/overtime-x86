#pragma once
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <span>

namespace ot {

/// C++20: a constrained template over a span.
template <std::integral T>
constexpr std::uint32_t checksum(std::span<const T> values) {
    std::uint32_t sum = 0;
    for (std::size_t i = 0; i < values.size(); ++i) {
        sum = sum * 31u + static_cast<std::uint32_t>(values[i]) + static_cast<std::uint32_t>(i);
    }
    return sum;
}

std::uint32_t checksum(const char *text);

}  // namespace ot

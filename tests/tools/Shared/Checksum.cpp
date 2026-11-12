#include "Checksum.hpp"
#include <algorithm>
#include <string_view>
#include <vector>

std::uint32_t ot::checksum(const char *text) {
    std::string_view view(text);
    std::vector<unsigned char> bytes(view.begin(), view.end());
    std::ranges::reverse(bytes);
    return checksum(std::span<const unsigned char>(bytes));
}

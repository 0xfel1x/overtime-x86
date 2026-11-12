#import "OTChecksum.h"
#include "Checksum.hpp"
#include <memory>
#include <string>

@implementation OTChecksum

+ (uint32_t)checksumOf:(NSString *)text {
    auto copy = std::make_unique<std::string>(text.UTF8String);
    return ot::checksum(copy->c_str());
}

@end

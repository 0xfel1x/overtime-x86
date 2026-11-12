#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ front for the C++ code in Checksum.hpp.
@interface OTChecksum : NSObject
+ (uint32_t)checksumOf:(NSString *)text;
@end

NS_ASSUME_NONNULL_END

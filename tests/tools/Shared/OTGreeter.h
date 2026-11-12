#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// An Objective-C class used from Swift through the bridging header.
@interface OTGreeter : NSObject
- (NSString *)greetingFor:(NSString *)name;
@property (class, readonly) NSString *platformName;
@end

NS_ASSUME_NONNULL_END

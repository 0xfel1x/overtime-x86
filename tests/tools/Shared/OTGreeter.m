@import Foundation;
#if TARGET_OS_OSX
@import AppKit;
#else
@import UIKit;
#endif
#import "OTGreeter.h"

@implementation OTGreeter

- (NSString *)greetingFor:(NSString *)name {
    return [NSString stringWithFormat:@"Hello, %@", name];
}

+ (NSString *)platformName {
#if TARGET_OS_OSX
    return [NSString stringWithFormat:@"AppKit %.0f", NSAppKitVersionNumber];
#else
    return [NSString stringWithFormat:@"UIKit, %@", NSStringFromClass(UIView.class)];
#endif
}

@end

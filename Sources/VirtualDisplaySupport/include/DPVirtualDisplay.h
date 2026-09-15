#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// A process-owned portrait display. Releasing it disconnects the display.
@interface DPVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (nullable instancetype)initWithWidth:(uint32_t)width
                               height:(uint32_t)height
                                error:(NSError **)error;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END

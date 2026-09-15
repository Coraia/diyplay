#import "DPVirtualDisplay.h"

// CoreGraphics exposes these classes at runtime but not in its public headers.
// Resolve classes dynamically so an unavailable API fails only this preset.
@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) uint32_t vendorID, productID, serialNum;
@property(nonatomic) uint32_t maxPixelsWide, maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(nonatomic, strong) dispatch_queue_t queue;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)rate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) uint32_t hiDPI;
@property(nonatomic, copy) NSArray *modes;
@end

@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

@implementation DPVirtualDisplay {
    CGVirtualDisplay *_display;
}

- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    @try {
        Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
        Class displayClass = NSClassFromString(@"CGVirtualDisplay");
        if (!descriptorClass || !modeClass || !settingsClass || !displayClass) {
            [NSException raise:@"Unavailable" format:@"当前 macOS 不支持手机竖屏模式。"];
        }

        CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
        descriptor.name = @"Diyplay 手机远程";
        descriptor.vendorID = 0xF15F;
        descriptor.productID = 0x0001;
        descriptor.serialNum = 0xD1700001;
        descriptor.maxPixelsWide = width * 2;
        descriptor.maxPixelsHigh = height * 2;
        descriptor.sizeInMillimeters = CGSizeMake(width * 2 * 25.4 / 220, height * 2 * 25.4 / 220);
        descriptor.redPrimary = CGPointMake(0.64, 0.33);
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        descriptor.queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

        CGVirtualDisplayMode *anchor = [[modeClass alloc] initWithWidth:width * 2
                                                               height:height * 2 refreshRate:60];
        CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:width height:height refreshRate:60];
        CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
        settings.hiDPI = 1;
        settings.modes = @[anchor, mode];
        _display = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!_display || ![_display applySettings:settings]) {
            [NSException raise:@"Configuration" format:@"macOS 未能创建手机竖屏模式。"];
        }
        return self;
    } @catch (NSException *exception) {
        _display = nil;
        if (error) {
            *error = [NSError errorWithDomain:@"com.coraia.diyplay.phone-remote"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"手机竖屏模式不可用。"}];
        }
        return nil;
    }
}

- (CGDirectDisplayID)displayID {
    return _display.displayID;
}

- (void)invalidate {
    _display = nil;
}

@end

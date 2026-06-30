#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges UNCATCHABLE Objective-C exceptions into Swift-catchable errors.
///
/// Some AVFoundation setters (notably `AVCaptureDevice.activeFormat`,
/// `activeColorSpace`, and `activeVideoMin/MaxFrameDuration`) raise
/// `NSInvalidArgumentException` for format/colour-space/frame-rate combinations
/// that a given physical device does not accept. An ObjC exception is NOT a Swift
/// error: it unwinds straight through `do/catch` and aborts the process
/// (SIGABRT / EXC_BAD_ACCESS at launch). `SFObjC.catching` runs a block inside an
/// ObjC `@try/@catch` so the camera-format negotiation can degrade to a thrown
/// Swift error (handled -> `.failed`) instead of crashing on an untested device.
@interface SFObjC : NSObject

/// Run `block`; if it raises an ObjC exception, capture it as an `NSError`
/// (domain `SFObjCException`) and return NO. Imported to Swift as a throwing
/// function: `try SFObjC.catching { ... }`.
+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

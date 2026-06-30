// Objective-C / C bridging header for the SixFour app target.
// Exposes the native Zig kernel C ABI to Swift.
#import "include/sixfour_native.h"
// ObjC exception -> Swift error shim (for uncatchable AVFoundation NSExceptions).
#import "SFObjC.h"

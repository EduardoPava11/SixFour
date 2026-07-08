// Objective-C bridging header for the SixFour app target.
// The former Zig C-ABI import (sixfour_native.h) is gone: the kernel core is
// pure Swift (SixFour/Kernels/, 2026-07-06) with the same s4_* names, so Swift
// call sites need no import at all.
// ObjC exception -> Swift error shim (for uncatchable AVFoundation NSExceptions).
#import "SFObjC.h"

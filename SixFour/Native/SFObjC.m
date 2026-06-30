#import "SFObjC.h"

@implementation SFObjC

+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error {
    @try {
        block();
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"%@: %@",
                              exception.name,
                              exception.reason ?: @"(no reason)"];
            *error = [NSError errorWithDomain:@"SFObjCException"
                                         code:0
                                     userInfo:@{ NSLocalizedDescriptionKey: desc }];
        }
        return NO;
    }
}

@end

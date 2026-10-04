#import "HardyFlowObjC.h"

BOOL HardyFlowTryCatch(void (NS_NOESCAPE ^ _Nonnull block)(void), NSError * _Nullable * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = exception.reason ?: @"Unknown Objective-C exception";
            if (exception.name) {
                userInfo[@"ExceptionName"] = exception.name;
            }
            if (exception.userInfo) {
                userInfo[@"ExceptionUserInfo"] = exception.userInfo;
            }
            *error = [NSError errorWithDomain:@"com.hardyflow.exception" code:-1 userInfo:userInfo];
        }
        return NO;
    }
}

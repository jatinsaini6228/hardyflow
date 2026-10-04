#import <Foundation/Foundation.h>

//! Project version number for HardyFlowObjC.
FOUNDATION_EXPORT double HardyFlowObjCVersionNumber;

//! Project version string for HardyFlowObjC.
FOUNDATION_EXPORT const unsigned char HardyFlowObjCVersionString[];

#ifdef __cplusplus
extern "C" {
#endif

/// Executes an arbitrary block within an Objective-C @try / @catch block,
/// preventing NSExceptions (e.g. from CoreAudio or AVAudioEngine) from aborting the process.
BOOL HardyFlowTryCatch(void (NS_NOESCAPE ^ _Nonnull block)(void), NSError * _Nullable * _Nullable error);

#ifdef __cplusplus
}
#endif

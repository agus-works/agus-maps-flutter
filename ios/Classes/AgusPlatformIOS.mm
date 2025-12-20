/// AgusPlatformIOS.mm
/// 
/// Initialization bridge for CoMaps Platform on iOS.
/// This file provides C functions to initialize the CoMaps Platform
/// with custom paths for use in a Flutter plugin context.
///
/// IMPORTANT: We do NOT reimplement Platform methods here!
/// The CoMaps XCFramework (libcomaps.a) already contains the full
/// iOS Platform implementation. We only call initialization methods.

#import "AgusPlatformIOS.h"

#include "platform/platform.hpp"
#include "base/logging.hpp"

#import <Foundation/Foundation.h>

#pragma mark - C Interface

extern "C" {

void AgusPlatformIOS_InitPaths(const char* resourcePath, const char* writablePath)
{
    if (!resourcePath || !writablePath)
    {
        LOG(LERROR, ("AgusPlatformIOS_InitPaths: null paths provided"));
        return;
    }
    
    Platform & platform = GetPlatform();
    
    // Set the resources directory (fonts, styles, data files)
    platform.SetResourceDir(resourcePath);
    
    // Set the writable directory (maps, settings, cache)
    platform.SetWritableDirForTests(writablePath);
    
    LOG(LINFO, ("AgusPlatformIOS initialized:",
                "resources =", resourcePath,
                "writable =", writablePath));
}

void* AgusPlatformIOS_GetInstance(void)
{
    return &GetPlatform();
}

} // extern "C"

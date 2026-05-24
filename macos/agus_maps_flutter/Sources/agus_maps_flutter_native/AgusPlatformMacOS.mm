/// AgusPlatformMacOS.mm
/// 
/// Initialization bridge for CoMaps Platform on macOS.
/// This file provides C functions to initialize the CoMaps Platform
/// with custom paths for use in a Flutter plugin context.
///
/// IMPORTANT: We do NOT reimplement Platform methods here!
/// The CoMaps XCFramework (libcomaps.a) already contains the full
/// macOS Platform implementation. We only call initialization methods.

#import "AgusPlatformMacOS.h"

#include "platform/platform.hpp"
#include "base/logging.hpp"

#import <Foundation/Foundation.h>

#pragma mark - C Interface

extern "C" {

void AgusPlatformMacOS_InitPaths(const char* resourcePath, const char* writablePath)
{
    if (!resourcePath || !writablePath)
    {
        LOG(LERROR, ("AgusPlatformMacOS_InitPaths: null paths provided"));
        return;
    }
    
    Platform & platform = GetPlatform();
    
    // Set the resources directory (fonts, styles, data files)
    platform.SetResourceDir(resourcePath);
    
    // Set the writable directory (maps, settings, cache)
    platform.SetWritableDirForTests(writablePath);
    
    LOG(LINFO, ("AgusPlatformMacOS initialized:",
                "resources =", resourcePath,
                "writable =", writablePath));
}

void* AgusPlatformMacOS_GetInstance(void)
{
    return &GetPlatform();
}

} // extern "C"

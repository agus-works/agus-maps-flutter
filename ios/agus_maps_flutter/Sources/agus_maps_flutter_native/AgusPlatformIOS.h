#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the iOS platform with resource and writable paths
/// @param resourcePath Path to read-only resources (fonts, data files)
/// @param writablePath Path to writable directory (maps, settings)
void AgusPlatformIOS_InitPaths(const char* resourcePath, const char* writablePath);

/// Get the shared platform instance
/// Called by Platform::GetPlatform() to get the singleton
void* AgusPlatformIOS_GetInstance(void);

#ifdef __cplusplus
}
#endif

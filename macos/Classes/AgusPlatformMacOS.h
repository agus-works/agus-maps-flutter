#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the macOS platform with resource and writable paths
/// @param resourcePath Path to read-only resources (fonts, data files)
/// @param writablePath Path to writable directory (maps, settings)
void AgusPlatformMacOS_InitPaths(const char* resourcePath, const char* writablePath);

/// Get the shared platform instance
/// Called by Platform::GetPlatform() to get the singleton
void* AgusPlatformMacOS_GetInstance(void);

#ifdef __cplusplus
}
#endif

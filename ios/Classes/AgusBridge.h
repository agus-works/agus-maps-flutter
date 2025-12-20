/// AgusBridge.h
/// 
/// C interface declarations for Swift to call native rendering functions.
/// These functions are implemented in agus_maps_flutter_ios.mm

#pragma once

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Called when Swift creates a new map surface
/// @param textureId Flutter texture ID
/// @param pixelBuffer CVPixelBuffer for rendering target
/// @param width Surface width in pixels
/// @param height Surface height in pixels
/// @param density Screen density
void agus_native_set_surface(
    int64_t textureId,
    CVPixelBufferRef pixelBuffer,
    int32_t width,
    int32_t height,
    float density
);

/// Called when Swift resizes the surface
void agus_native_on_size_changed(int32_t width, int32_t height);

/// Called when Swift destroys the surface
void agus_native_on_surface_destroyed(void);

/// Frame ready callback type
typedef void (*AgusFrameReadyCallback)(void);

/// Set the callback for frame ready notifications
void agus_set_frame_ready_callback(AgusFrameReadyCallback callback);

#ifdef __cplusplus
}
#endif

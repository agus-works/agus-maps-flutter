// Copyright 2025 The Agus Maps Flutter Authors
// SPDX-License-Identifier: MIT

#ifndef FLUTTER_PLUGIN_AGUS_MAPS_FLUTTER_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_AGUS_MAPS_FLUTTER_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

/// Registers the Agus Maps Flutter plugin with the Flutter engine.
/// This function is called automatically by Flutter's plugin registration system.
FLUTTER_PLUGIN_EXPORT void AgusMapsFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_AGUS_MAPS_FLUTTER_PLUGIN_C_API_H_

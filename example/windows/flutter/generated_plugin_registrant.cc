//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <agus_maps_flutter/agus_maps_flutter_plugin_c_api.h>
#include <connectivity_plus/connectivity_plus_windows_plugin.h>
#include <geolocator_windows/geolocator_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AgusMapsFlutterPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AgusMapsFlutterPluginCApi"));
  ConnectivityPlusWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ConnectivityPlusWindowsPlugin"));
  GeolocatorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("GeolocatorWindows"));
}

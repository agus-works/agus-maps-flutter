// Copyright 2025 The Agus Maps Flutter Authors
// SPDX-License-Identifier: MIT

#ifndef FLUTTER_PLUGIN_AGUS_MAPS_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_AGUS_MAPS_FLUTTER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _AgusMapsFlutterPlugin AgusMapsFlutterPlugin;
typedef struct {
  GObjectClass parent_class;
} AgusMapsFlutterPluginClass;

FLUTTER_PLUGIN_EXPORT GType agus_maps_flutter_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void agus_maps_flutter_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_AGUS_MAPS_FLUTTER_PLUGIN_H_

# ProGuard/R8 rules for agus_maps_flutter plugin
# These rules are automatically included by consumer apps via consumerProguardFiles

# Keep all classes in the plugin package that are accessed via JNI
# The native code uses JNI reflection to create Java objects at runtime
-keep class app.agus.maps.agus_maps_flutter.AgusMapsApi { *; }
-keep class app.agus.maps.agus_maps_flutter.AgusMapsApi$* { *; }
-keep class app.agus.maps.agus_maps_flutter.AgusMapsFlutterPlugin { *; }

# Keep classes that are created from native code via JNI
# These inner classes and their builders are instantiated from C++ code
-keepclassmembers class app.agus.maps.agus_maps_flutter.AgusMapsApi$PlacePageData { *; }
-keepclassmembers class app.agus.maps.agus_maps_flutter.AgusMapsApi$PlacePageData$Builder { *; }

# Keep native method signatures
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enum values (used by Pigeon-generated API)
-keepclassmembers enum app.agus.maps.agus_maps_flutter.** {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

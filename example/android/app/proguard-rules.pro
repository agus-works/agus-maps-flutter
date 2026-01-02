# Proguard/R8 rules for the example app.
# Keep this minimal: broad Flutter keeps can inadvertently retain optional
# classes (like Play Core deferred components) that aren't on the classpath.

# We explicitly call GeneratedPluginRegistrant from MainActivity.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Federated plugins using Pigeon (channel names: dev.flutter.pigeon.*)
-keep class dev.flutter.pigeon.** { *; }

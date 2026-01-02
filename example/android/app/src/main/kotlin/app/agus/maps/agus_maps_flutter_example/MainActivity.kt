package app.agus.maps.agus_maps_flutter_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		// Explicitly register plugins to guarantee platform channels are available
		// in release builds (e.g., shared_preferences uses Pigeon channels).
		GeneratedPluginRegistrant.registerWith(flutterEngine)
	}
}

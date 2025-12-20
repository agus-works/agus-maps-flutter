package app.agus.maps.agus_maps_flutter;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.DisplayMetrics;
import android.view.WindowManager;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.embedding.engine.loader.FlutterLoader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;

import io.flutter.view.TextureRegistry;
import android.view.Surface;

/** AgusMapsFlutterPlugin */
public class AgusMapsFlutterPlugin implements FlutterPlugin, MethodCallHandler {
  private static final String TAG = "AgusMapsFlutter";
  
  private MethodChannel channel;
  private Context context;
  private TextureRegistry textureRegistry;
  private TextureRegistry.SurfaceProducer surfaceProducer;
  private int surfaceWidth = 0;
  private int surfaceHeight = 0;
  private float density = 2.0f;
  private android.os.Handler mainHandler;
  
  static {
      System.loadLibrary("agus_maps_flutter");
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "agus_maps_flutter");
    channel.setMethodCallHandler(this);
    context = flutterPluginBinding.getApplicationContext();
    textureRegistry = flutterPluginBinding.getTextureRegistry();
    mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    
    // Initialize native frame callback
    nativeInitFrameCallback();
    
    // Get display metrics for proper density
    WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
    if (wm != null) {
        DisplayMetrics dm = new DisplayMetrics();
        wm.getDefaultDisplay().getMetrics(dm);
        density = dm.density;
        android.util.Log.d(TAG, "Display density: " + density);
    }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.equals("extractMap")) {
      // ... existing code ...
      String assetPath = call.argument("assetPath");
      if (assetPath == null) {
        result.error("INVALID_ARGUMENT", "assetPath is null", null);
        return;
      }
      
      new Thread(() -> {
          try {
              String extractedPath = extractMap(assetPath);
              new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                  result.success(extractedPath);
              });
          } catch (Exception e) {
              android.util.Log.e("AgusMapsFlutter", "Error extracting map", e);
              new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                  result.error("EXTRACTION_FAILED", e.getMessage(), null);
              });
          }
      }).start();

    } else if (call.method.equals("extractDataFiles")) {
        // Extract all CoMaps data files from assets/comaps_data/
        new Thread(() -> {
            try {
                String dataPath = extractDataFiles();
                new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                    result.success(dataPath);
                });
            } catch (Exception e) {
                android.util.Log.e("AgusMapsFlutter", "Error extracting data files", e);
                new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                    result.error("EXTRACTION_FAILED", e.getMessage(), null);
                });
            }
        }).start();
        
    } else if (call.method.equals("getApkPath")) {
        result.success(context.getApplicationInfo().sourceDir);
    } else if (call.method.equals("createMapSurface")) {
        // Get requested size from Flutter (in logical pixels)
        Integer width = call.argument("width");
        Integer height = call.argument("height");
        
        // Use screen size as default if not specified
        if (width == null || height == null || width <= 0 || height <= 0) {
            WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
            DisplayMetrics dm = new DisplayMetrics();
            wm.getDefaultDisplay().getMetrics(dm);
            width = dm.widthPixels;
            height = dm.heightPixels;
        }
        
        surfaceWidth = width;
        surfaceHeight = height;
        
        android.util.Log.d(TAG, "createMapSurface: " + surfaceWidth + "x" + surfaceHeight + " density=" + density);
        
        surfaceProducer = textureRegistry.createSurfaceProducer();
        surfaceProducer.setSize(surfaceWidth, surfaceHeight);
        
        // Set up surface lifecycle callback
        surfaceProducer.setCallback(new TextureRegistry.SurfaceProducer.Callback() {
            @Override
            public void onSurfaceAvailable() {
                android.util.Log.d(TAG, "onSurfaceAvailable: recreating surface");
                Surface surface = surfaceProducer.getSurface();
                nativeOnSurfaceChanged(surfaceProducer.id(), surface, surfaceWidth, surfaceHeight, density);
            }
            
            @Override
            public void onSurfaceDestroyed() {
                android.util.Log.d(TAG, "onSurfaceDestroyed: pausing rendering");
                nativeOnSurfaceDestroyed();
            }
        });
        
        // Initial surface setup
        Surface surface = surfaceProducer.getSurface();
        nativeSetSurface(surfaceProducer.id(), surface, surfaceWidth, surfaceHeight, density);
        result.success(surfaceProducer.id());
    } else if (call.method.equals("resizeMapSurface")) {
        Integer width = call.argument("width");
        Integer height = call.argument("height");
        
        if (width != null && height != null && width > 0 && height > 0 && surfaceProducer != null) {
            surfaceWidth = width;
            surfaceHeight = height;
            surfaceProducer.setSize(width, height);
            nativeOnSizeChanged(width, height);
            result.success(true);
        } else {
            result.error("INVALID_STATE", "Surface not created or invalid size", null);
        }
    } else {
      result.notImplemented();
    }
  }

  private native void nativeSetSurface(long textureId, Surface surface, int width, int height, float density);
  private native void nativeOnSurfaceChanged(long textureId, Surface surface, int width, int height, float density);
  private native void nativeOnSurfaceDestroyed();
  private native void nativeOnSizeChanged(int width, int height);
  private native void nativeInitFrameCallback();
  private native void nativeCleanupFrameCallback();

  /**
   * Called from native code when an active frame is rendered.
   * With SurfaceProducer, frames are automatically picked up by the Flutter engine
   * when rendered to the surface. This callback can be used for debugging/logging
   * if needed, but no explicit notification to Flutter is required.
   */
  @SuppressWarnings("unused") // Called from native code
  public void onFrameReady() {
    // SurfaceProducer automatically notifies Flutter when frames are rendered
    // to the Surface. No explicit registration is needed.
    // This callback is kept for potential debugging purposes.
  }

  private String extractMap(String assetPath) throws IOException {
    android.util.Log.d("AgusMapsFlutter", "Extracting asset: " + assetPath);
    String fullAssetPath = io.flutter.FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath);
    
    File filesDir = context.getFilesDir();
    File outFile = new File(filesDir, new File(assetPath).getName());
    
    if (outFile.exists()) {
        android.util.Log.d("AgusMapsFlutter", "Map already exists at: " + outFile.getAbsolutePath());
        return outFile.getAbsolutePath();
    }

    AssetManager assetManager = context.getAssets();
    try (InputStream in = assetManager.open(fullAssetPath);
         OutputStream out = new FileOutputStream(outFile)) {
        byte[] buffer = new byte[32 * 1024]; // 32KB buffer
        int read;
        while ((read = in.read(buffer)) != -1) {
            out.write(buffer, 0, read);
        }
    }
    android.util.Log.d("AgusMapsFlutter", "Map extracted to: " + outFile.getAbsolutePath());
    return outFile.getAbsolutePath();
  }

  private String extractDataFiles() throws IOException {
    android.util.Log.d("AgusMapsFlutter", "Extracting CoMaps data files...");
    
    // Extract data files directly to the files directory (not a subdirectory)
    // This is because platform_android.cpp looks for files in m_writableDir directly
    File filesDir = context.getFilesDir();
    
    // Check if data is already extracted by looking for a marker file
    File markerFile = new File(filesDir, ".comaps_data_extracted");
    if (markerFile.exists()) {
        android.util.Log.d("AgusMapsFlutter", "Data already extracted at: " + filesDir.getAbsolutePath());
        return filesDir.getAbsolutePath();
    }
    
    AssetManager assetManager = context.getAssets();
    String assetPrefix = io.flutter.FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/comaps_data");
    
    // Extract all files from assets/comaps_data directly to files directory
    extractAssetsRecursive(assetManager, assetPrefix, filesDir);
    
    // Create marker file
    markerFile.createNewFile();
    
    android.util.Log.d("AgusMapsFlutter", "Data extracted to: " + filesDir.getAbsolutePath());
    return filesDir.getAbsolutePath();
  }

  private void extractAssetsRecursive(AssetManager assetManager, String assetPath, File outDir) throws IOException {
    String[] files = assetManager.list(assetPath);
    android.util.Log.d("AgusMapsFlutter", "Listing assets at: " + assetPath + " found: " + (files != null ? files.length : 0) + " items");
    if (files == null || files.length == 0) {
        // It's a file, not a directory
        try (InputStream in = assetManager.open(assetPath)) {
            String fileName = new File(assetPath).getName();
            File outFile = new File(outDir, fileName);
            android.util.Log.d("AgusMapsFlutter", "Extracting file: " + assetPath + " -> " + outFile.getAbsolutePath());
            
            try (OutputStream out = new FileOutputStream(outFile)) {
                byte[] buffer = new byte[32 * 1024];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
            }
        }
    } else {
        // It's a directory - list what we found
        for (int i = 0; i < Math.min(files.length, 5); i++) {
            android.util.Log.d("AgusMapsFlutter", "  Found item: " + files[i]);
        }
        if (files.length > 5) {
            android.util.Log.d("AgusMapsFlutter", "  ... and " + (files.length - 5) + " more items");
        }
        
        for (String file : files) {
            String childPath = assetPath + "/" + file;
            File childDir = outDir;
            
            // Check if this child is a directory
            String[] subFiles = assetManager.list(childPath);
            if (subFiles != null && subFiles.length > 0) {
                // It's a directory, create it
                childDir = new File(outDir, file);
                android.util.Log.d("AgusMapsFlutter", "Creating directory: " + childDir.getAbsolutePath());
                childDir.mkdirs();
            }
            
            extractAssetsRecursive(assetManager, childPath, childDir);
        }
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    // Cleanup native frame callback
    nativeCleanupFrameCallback();
    channel.setMethodCallHandler(null);
  }
}

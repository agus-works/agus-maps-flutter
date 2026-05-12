package app.agus.maps.agus_maps_flutter;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.DisplayMetrics;
import android.view.WindowManager;
import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.loader.FlutterLoader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import java.util.Locale;

import io.flutter.view.TextureRegistry;
import android.view.Surface;

/** AgusMapsFlutterPlugin */
public class AgusMapsFlutterPlugin implements FlutterPlugin, AgusMapsApi.AgusMapsHostApi {
  private static final String TAG = "AgusMapsFlutter";

  private Context context;
  private TextureRegistry textureRegistry;
  private TextureRegistry.SurfaceProducer surfaceProducer;
  private int surfaceWidth = 0;
  private int surfaceHeight = 0;
  private float density = 2.0f;
  private android.os.Handler mainHandler;
    private AgusMapsApi.AgusMapsFlutterApi flutterApi;
    private boolean mapReadySent = false;
  
  // Flag to ensure native library is loaded only once
  private static volatile boolean nativeLibraryLoaded = false;
  private static final Object loadLock = new Object();
  
  /**
   * Loads the native library if not already loaded.
   * Called lazily to avoid interfering with Flutter plugin registration.
   */
  private static void ensureNativeLibraryLoaded() {
    if (!nativeLibraryLoaded) {
      synchronized (loadLock) {
        if (!nativeLibraryLoaded) {
          System.loadLibrary("agus_maps_flutter");
          nativeLibraryLoaded = true;
        }
      }
    }
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    // Load native library lazily - after Flutter plugin system is initialized
    ensureNativeLibraryLoaded();

        AgusMapsApi.AgusMapsHostApi.setUp(flutterPluginBinding.getBinaryMessenger(), this);
        flutterApi = new AgusMapsApi.AgusMapsFlutterApi(flutterPluginBinding.getBinaryMessenger());
    context = flutterPluginBinding.getApplicationContext();
    textureRegistry = flutterPluginBinding.getTextureRegistry();
    mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    
    // Initialize native frame callback
    nativeInitFrameCallback();

    // Initialize native locale for localized type names
    Locale locale = Locale.getDefault();
    String localeTag = locale != null ? locale.toLanguageTag() : "en";
    nativeSetLocale(localeTag);
    
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
    public void extractMap(@NonNull String assetPath, @NonNull AgusMapsApi.Result<String> result) {
        new Thread(() -> {
            try {
                String extractedPath = extractMap(assetPath);
                mainHandler.post(() -> result.success(extractedPath));
            } catch (Exception e) {
                android.util.Log.e(TAG, "Error extracting map", e);
                mainHandler.post(() -> result.error(new AgusMapsApi.FlutterError(
                        "EXTRACTION_FAILED", e.getMessage(), null)));
            }
        }).start();
    }

    @Override
    public void extractDataFiles(@NonNull AgusMapsApi.Result<String> result) {
        new Thread(() -> {
            try {
                String dataPath = extractDataFiles();
                mainHandler.post(() -> result.success(dataPath));
            } catch (Exception e) {
                android.util.Log.e(TAG, "Error extracting data files", e);
                mainHandler.post(() -> result.error(new AgusMapsApi.FlutterError(
                        "EXTRACTION_FAILED", e.getMessage(), null)));
            }
        }).start();
    }

    @Override
    public void getApkPath(@NonNull AgusMapsApi.Result<String> result) {
        result.success(context.getApplicationInfo().sourceDir);
    }

    @Override
    public void createMapSurface(
            @NonNull AgusMapsApi.CreateMapSurfaceRequest request,
            @NonNull AgusMapsApi.Result<Long> result) {
        Long widthArg = request.getWidth();
        Long heightArg = request.getHeight();
        Double densityArg = request.getDensity();

        if (densityArg != null && densityArg > 0) {
            density = densityArg.floatValue();
        }

        int width = widthArg != null ? widthArg.intValue() : 0;
        int height = heightArg != null ? heightArg.intValue() : 0;

        if (width <= 0 || height <= 0) {
            WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
            DisplayMetrics dm = new DisplayMetrics();
            wm.getDefaultDisplay().getMetrics(dm);
            width = dm.widthPixels;
            height = dm.heightPixels;
        }

        surfaceWidth = width;
        surfaceHeight = height;
        mapReadySent = false;

        android.util.Log.d(TAG, "createMapSurface: " + surfaceWidth + "x" + surfaceHeight + " density=" + density);

        surfaceProducer = textureRegistry.createSurfaceProducer();
        surfaceProducer.setSize(surfaceWidth, surfaceHeight);

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

        Surface surface = surfaceProducer.getSurface();
        nativeSetSurface(surfaceProducer.id(), surface, surfaceWidth, surfaceHeight, density);
        result.success(surfaceProducer.id());
        sendRenderStateChanged(AgusMapsApi.RenderState.ACTIVE, surfaceProducer.id());
    }

    @Override
    public void resizeMapSurface(
            @NonNull AgusMapsApi.ResizeMapSurfaceRequest request,
            @NonNull AgusMapsApi.Result<Boolean> result) {
        if (surfaceProducer == null) {
            result.error(new AgusMapsApi.FlutterError(
                    "INVALID_STATE", "Surface not created or invalid size", null));
            return;
        }

        int width = request.getWidth().intValue();
        int height = request.getHeight().intValue();
        Double densityArg = request.getDensity();

        if (width > 0 && height > 0) {
            float requestedDensity = density;
            if (densityArg != null && densityArg > 0) {
                requestedDensity = densityArg.floatValue();
            }

            boolean sizeUnchanged = width == surfaceWidth && height == surfaceHeight;
            boolean densityUnchanged = Math.abs(requestedDensity - density) < 0.0001f;

            if (sizeUnchanged && densityUnchanged) {
                result.success(true);
                return;
            }

            if (!sizeUnchanged) {
                surfaceWidth = width;
                surfaceHeight = height;
                surfaceProducer.setSize(width, height);
                nativeOnSizeChanged(width, height);
            }

            if (!densityUnchanged) {
                density = requestedDensity;
                nativeSetVisualScale(density);
            }

            result.success(true);
        } else {
            result.error(new AgusMapsApi.FlutterError(
                    "INVALID_STATE", "Surface not created or invalid size", null));
        }
    }

    @Override
    public void destroyMapSurface(@NonNull AgusMapsApi.Result<Boolean> result) {
        if (surfaceProducer == null) {
            result.success(false);
            return;
        }

        nativeOnSurfaceDestroyed();
        try {
            surfaceProducer.release();
        } catch (Exception e) {
            android.util.Log.w(TAG, "Failed to release surface producer", e);
        }
        surfaceProducer = null;
        surfaceWidth = 0;
        surfaceHeight = 0;
        mapReadySent = false;

        sendRenderStateChanged(AgusMapsApi.RenderState.IDLE, null);
        result.success(true);
    }

    @Override
    public void updateMapPointer(
            @NonNull AgusMapsApi.MapPointerUpdateRequest request,
            @NonNull AgusMapsApi.NullableResult<AgusMapsApi.MapPointerCoordinate> result) {
        double[] latLon = new double[2];
        int projected = nativeUpdateMapPointer(
                request.getPhysicalX(),
                request.getPhysicalY(),
                request.getInsideMap() ? 1 : 0,
                latLon);
        if (projected != 1) {
            result.success(null);
            return;
        }
        result.success(new AgusMapsApi.MapPointerCoordinate.Builder()
                .setPhysicalX(request.getPhysicalX())
                .setPhysicalY(request.getPhysicalY())
                .setInsideMap(request.getInsideMap())
                .setLat(latLon[0])
                .setLon(latLon[1])
                .build());
    }

    @Override
    public void updateDrapeInteractionGeometry(
            @NonNull AgusMapsApi.DrapeInteractionGeometryRequest request,
            @NonNull AgusMapsApi.Result<Boolean> result) {
        AgusMapsApi.DrapeInteractionLineStyle style = request.getLineStyle();
        nativeUpdateDrapeInteractionGeometry(
                request.getMode().intValue(),
                request.getGeometryWkt(),
                style.getColorRed().intValue(),
                style.getColorGreen().intValue(),
                style.getColorBlue().intValue(),
                style.getOpacity(),
                style.getWidth(),
                style.getDashed() ? 1 : 0,
                style.getDashLength(),
                style.getGapLength());
        result.success(true);
    }

    @Override
    public void getCurrentPlacePage(@NonNull AgusMapsApi.NullableResult<AgusMapsApi.PlacePageData> result) {
        result.success(nativeGetCurrentPlacePage());
    }

    @Override
    public void clearPlacePageSelection(@NonNull AgusMapsApi.Result<Boolean> result) {
        nativeClearPlacePageSelection();
        result.success(true);
    }


    private void sendRenderStateChanged(AgusMapsApi.RenderState state, Long surfaceId) {
        if (flutterApi == null) return;
        flutterApi.onRenderStateChanged(state, surfaceId, new AgusMapsApi.VoidResult() {
            @Override
            public void success() {}

            @Override
            public void error(@NonNull Throwable error) {
                android.util.Log.w(TAG, "Render state callback failed", error);
            }
        });
    }

  private native void nativeSetSurface(long textureId, Surface surface, int width, int height, float density);
  private native void nativeOnSurfaceChanged(long textureId, Surface surface, int width, int height, float density);
  private native void nativeOnSurfaceDestroyed();
  private native void nativeOnSizeChanged(int width, int height);
    private native void nativeSetVisualScale(float density);
  private native void nativeInitFrameCallback();
  private native void nativeCleanupFrameCallback();
    private native void nativeSetLocale(String locale);
    private native AgusMapsApi.PlacePageData nativeGetCurrentPlacePage();
    private native void nativeClearPlacePageSelection();
    private native int nativeUpdateMapPointer(
            double physicalX, double physicalY, int insideMap, double[] latLon);
    private native void nativeUpdateDrapeInteractionGeometry(
            int mode,
            String geometryWkt,
            int red,
            int green,
            int blue,
            double opacity,
            double width,
            int dashed,
            double dashLength,
            double gapLength);

  /**
   * Called from native code when an active frame is rendered.
   * With SurfaceProducer, frames are automatically picked up by the Flutter engine
   * when rendered to the surface. This callback can be used for debugging/logging
   * if needed, but no explicit notification to Flutter is required.
   */
  @SuppressWarnings("unused") // Called from native code
    @Keep
  public void onFrameReady() {
        // SurfaceProducer requires an explicit scheduleFrame() to notify Flutter
        // that a new frame is available for composition.
        final TextureRegistry.SurfaceProducer producer = surfaceProducer;
        if (producer == null) return;

        // Ensure we call into Flutter engine APIs on the main thread.
        if (mainHandler != null) {
                        mainHandler.post(() -> {
                                producer.scheduleFrame();
                                if (!mapReadySent) {
                                        mapReadySent = true;
                                        sendMapReady(producer.id());
                                }
                        });
        } else {
            producer.scheduleFrame();
                        if (!mapReadySent) {
                                mapReadySent = true;
                                sendMapReady(producer.id());
                        }
        }
  }

    private void sendMapReady(long surfaceId) {
        if (flutterApi == null) return;
        flutterApi.onMapReady(surfaceId, new AgusMapsApi.VoidResult() {
            @Override
            public void success() {}

            @Override
            public void error(@NonNull Throwable error) {
                android.util.Log.w(TAG, "Map ready callback failed", error);
            }
        });
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
    File fontsDir = new File(filesDir, "fonts");
    File unicodeBlockFile = new File(fontsDir, "unicode_blocks.txt");
    File localizedTypesFile = new File(filesDir, "localized_types/en.lproj/LocalizableTypes.strings");
    File categoriesBrandsFile = new File(filesDir, "categories_brands.txt");
    File soundStringsFile = new File(filesDir, "sound-strings/en.json/localize.json");
    File lightSymbolsPng = new File(filesDir, "symbols/xxhdpi/light/symbols.png");
    File lightSymbolsSdf = new File(filesDir, "symbols/xxhdpi/light/symbols.sdf");
    File darkSymbolsPng = new File(filesDir, "symbols/xxhdpi/dark/symbols.png");
    File darkSymbolsSdf = new File(filesDir, "symbols/xxhdpi/dark/symbols.sdf");

    boolean symbolsReady =
            lightSymbolsPng.exists() && lightSymbolsPng.length() >= 100_000L &&
            darkSymbolsPng.exists() && darkSymbolsPng.length() >= 100_000L &&
            lightSymbolsSdf.exists() && lightSymbolsSdf.length() >= 1_000L &&
            darkSymbolsSdf.exists() && darkSymbolsSdf.length() >= 1_000L;
    
    // Check if data is already extracted AND essential files exist
    if (markerFile.exists() && unicodeBlockFile.exists() && localizedTypesFile.exists() && categoriesBrandsFile.exists() && soundStringsFile.exists() && symbolsReady) {
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
        AgusMapsApi.AgusMapsHostApi.setUp(binding.getBinaryMessenger(), null);
        flutterApi = null;
  }
}

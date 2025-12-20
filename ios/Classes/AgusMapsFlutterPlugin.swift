import Flutter
import UIKit
import Metal
import CoreVideo

/// AgusMapsFlutterPlugin - Flutter plugin for CoMaps rendering on iOS
///
/// This plugin implements:
/// - FlutterPlugin for MethodChannel communication
/// - FlutterTexture for zero-copy GPU texture sharing via CVPixelBuffer
///
/// Architecture:
/// 1. Flutter requests a map surface via MethodChannel
/// 2. Plugin creates CVPixelBuffer backed by IOSurface (Metal-compatible)
/// 3. Native CoMaps engine renders to MTLTexture derived from CVPixelBuffer
/// 4. Flutter samples the texture directly (zero-copy via IOSurface)
public class AgusMapsFlutterPlugin: NSObject, FlutterPlugin, FlutterTexture {
    
    // MARK: - Shared Instance for native callbacks
    
    /// Shared instance for native code to notify when frames are ready
    private static weak var sharedInstance: AgusMapsFlutterPlugin?
    
    /// Called by native code when a frame is ready
    @objc public static func notifyFrameReadyFromNative() {
        DispatchQueue.main.async {
            sharedInstance?.notifyFrameReady()
        }
    }
    
    // MARK: - Properties
    
    private var channel: FlutterMethodChannel?
    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    
    // CVPixelBuffer for zero-copy texture sharing
    private var pixelBuffer: CVPixelBuffer?
    private var textureCache: CVMetalTextureCache?
    private var metalDevice: MTLDevice?
    
    // Surface dimensions
    private var surfaceWidth: Int = 0
    private var surfaceHeight: Int = 0
    private var density: CGFloat = 2.0
    
    // Rendering state
    private var isRenderingEnabled: Bool = false
    
    // MARK: - FlutterPlugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "agus_maps_flutter",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = AgusMapsFlutterPlugin()
        instance.channel = channel
        instance.textureRegistry = registrar.textures()
        instance.density = UIScreen.main.scale
        
        // Store shared instance for native callbacks
        AgusMapsFlutterPlugin.sharedInstance = instance
        
        // Initialize Metal device
        instance.metalDevice = MTLCreateSystemDefaultDevice()
        if instance.metalDevice == nil {
            NSLog("[AgusMapsFlutter] Warning: Metal device not available")
        }
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        NSLog("[AgusMapsFlutter] Plugin registered, density=%.2f", instance.density)
    }
    
    // MARK: - FlutterTexture Protocol
    
    /// Called by Flutter engine to get the current frame's pixel buffer
    /// This is the zero-copy path - Flutter samples directly from our CVPixelBuffer
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = pixelBuffer else {
            return nil
        }
        return Unmanaged.passRetained(buffer)
    }
    
    /// Called when texture is about to be rendered
    public func onTextureUnregistered(_ texture: FlutterTexture) {
        NSLog("[AgusMapsFlutter] Texture unregistered")
        cleanupTexture()
    }
    
    // MARK: - MethodChannel Handler
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "extractMap":
            handleExtractMap(call: call, result: result)
            
        case "extractDataFiles":
            handleExtractDataFiles(result: result)
            
        case "getApkPath":
            // iOS equivalent: main bundle resource path
            result(Bundle.main.resourcePath)
            
        case "createMapSurface":
            handleCreateMapSurface(call: call, result: result)
            
        case "resizeMapSurface":
            handleResizeMapSurface(call: call, result: result)
            
        case "destroyMapSurface":
            handleDestroyMapSurface(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Map Asset Extraction
    
    private func handleExtractMap(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let assetPath = args["assetPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "assetPath is required", details: nil))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let extractedPath = try self.extractMapAsset(assetPath: assetPath)
                DispatchQueue.main.async {
                    result(extractedPath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "EXTRACTION_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func extractMapAsset(assetPath: String) throws -> String {
        NSLog("[AgusMapsFlutter] Extracting asset: %@", assetPath)
        
        // Get the Flutter asset path
        let flutterAssetPath = lookupKeyForAsset(assetPath)
        
        guard let bundlePath = Bundle.main.path(forResource: flutterAssetPath, ofType: nil) else {
            throw NSError(domain: "AgusMapsFlutter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Asset not found: \(assetPath)"
            ])
        }
        
        // Destination in Documents directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = (assetPath as NSString).lastPathComponent
        let destPath = documentsDir.appendingPathComponent(fileName)
        
        // Check if already extracted
        if FileManager.default.fileExists(atPath: destPath.path) {
            NSLog("[AgusMapsFlutter] Map already exists at: %@", destPath.path)
            return destPath.path
        }
        
        // Copy file
        try FileManager.default.copyItem(atPath: bundlePath, toPath: destPath.path)
        
        // Disable iCloud backup for map files
        var url = destPath
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
        
        NSLog("[AgusMapsFlutter] Map extracted to: %@", destPath.path)
        return destPath.path
    }
    
    private func handleExtractDataFiles(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dataPath = try self.extractDataFiles()
                DispatchQueue.main.async {
                    result(dataPath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "EXTRACTION_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func extractDataFiles() throws -> String {
        NSLog("[AgusMapsFlutter] Extracting CoMaps data files...")
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let markerFile = documentsDir.appendingPathComponent(".comaps_data_extracted")
        
        // Check if already extracted
        if FileManager.default.fileExists(atPath: markerFile.path) {
            NSLog("[AgusMapsFlutter] Data already extracted at: %@", documentsDir.path)
            return documentsDir.path
        }
        
        // Extract data files from bundle's comaps_data directory
        let dataAssetPath = lookupKeyForAsset("assets/comaps_data")
        if let bundleDataPath = Bundle.main.resourcePath?.appending("/\(dataAssetPath)"),
           FileManager.default.fileExists(atPath: bundleDataPath) {
            try extractDirectory(from: bundleDataPath, to: documentsDir.path)
        }
        
        // Create marker file
        FileManager.default.createFile(atPath: markerFile.path, contents: nil, attributes: nil)
        
        NSLog("[AgusMapsFlutter] Data files extracted to: %@", documentsDir.path)
        return documentsDir.path
    }
    
    private func extractDirectory(from sourcePath: String, to destPath: String) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(atPath: sourcePath)
        
        for item in contents {
            let sourceItem = (sourcePath as NSString).appendingPathComponent(item)
            let destItem = (destPath as NSString).appendingPathComponent(item)
            
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: sourceItem, isDirectory: &isDir) {
                if isDir.boolValue {
                    try fileManager.createDirectory(atPath: destItem, withIntermediateDirectories: true)
                    try extractDirectory(from: sourceItem, to: destItem)
                } else {
                    if !fileManager.fileExists(atPath: destItem) {
                        try fileManager.copyItem(atPath: sourceItem, toPath: destItem)
                    }
                }
            }
        }
    }
    
    // MARK: - Map Surface Management
    
    private func handleCreateMapSurface(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        
        // Get requested size or use screen size
        var width = args?["width"] as? Int ?? 0
        var height = args?["height"] as? Int ?? 0
        
        if width <= 0 || height <= 0 {
            let screenSize = UIScreen.main.bounds.size
            width = Int(screenSize.width * density)
            height = Int(screenSize.height * density)
        }
        
        surfaceWidth = width
        surfaceHeight = height
        
        NSLog("[AgusMapsFlutter] createMapSurface: %dx%d density=%.2f", width, height, density)
        
        // Create CVPixelBuffer for texture sharing
        do {
            try createPixelBuffer(width: width, height: height)
            
            // Register texture with Flutter
            guard let registry = textureRegistry else {
                result(FlutterError(code: "NO_REGISTRY", message: "Texture registry not available", details: nil))
                return
            }
            
            textureId = registry.register(self)
            isRenderingEnabled = true
            
            // Initialize native surface
            nativeSetSurface(textureId: textureId, width: Int32(width), height: Int32(height), density: Float(density))
            
            NSLog("[AgusMapsFlutter] Texture registered: id=%lld", textureId)
            result(textureId)
            
        } catch {
            result(FlutterError(code: "CREATE_FAILED", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleResizeMapSurface(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let width = args["width"] as? Int,
              let height = args["height"] as? Int,
              width > 0, height > 0 else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Valid width and height required", details: nil))
            return
        }
        
        surfaceWidth = width
        surfaceHeight = height
        
        do {
            try createPixelBuffer(width: width, height: height)
            nativeOnSizeChanged(width: Int32(width), height: Int32(height))
            
            // Notify Flutter of texture update
            textureRegistry?.textureFrameAvailable(textureId)
            
            result(true)
        } catch {
            result(FlutterError(code: "RESIZE_FAILED", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleDestroyMapSurface(result: @escaping FlutterResult) {
        cleanupTexture()
        result(true)
    }
    
    // MARK: - CVPixelBuffer Creation (Zero-Copy)
    
    private func createPixelBuffer(width: Int, height: Int) throws {
        // Release existing buffer
        pixelBuffer = nil
        
        // Create CVPixelBuffer with Metal and IOSurface compatibility
        // This enables zero-copy texture sharing between CoMaps and Flutter
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        var newBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &newBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = newBuffer else {
            throw NSError(domain: "AgusMapsFlutter", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create CVPixelBuffer: \(status)"
            ])
        }
        
        pixelBuffer = buffer
        
        // Create Metal texture cache if needed
        if textureCache == nil, let device = metalDevice {
            var cache: CVMetalTextureCache?
            let cacheStatus = CVMetalTextureCacheCreate(
                kCFAllocatorDefault,
                nil,
                device,
                nil,
                &cache
            )
            
            if cacheStatus == kCVReturnSuccess {
                textureCache = cache
            } else {
                NSLog("[AgusMapsFlutter] Warning: Failed to create Metal texture cache: %d", cacheStatus)
            }
        }
        
        NSLog("[AgusMapsFlutter] CVPixelBuffer created: %dx%d (Metal=%@, IOSurface=%@)",
              width, height,
              CVPixelBufferGetIOSurface(buffer) != nil ? "YES" : "NO",
              metalDevice != nil ? "YES" : "NO")
    }
    
    private func cleanupTexture() {
        isRenderingEnabled = false
        
        if textureId >= 0, let registry = textureRegistry {
            registry.unregisterTexture(textureId)
            textureId = -1
        }
        
        pixelBuffer = nil
        
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        textureCache = nil
        
        nativeOnSurfaceDestroyed()
        
        NSLog("[AgusMapsFlutter] Texture cleaned up")
    }
    
    // MARK: - Rendering
    
    /// Called by native code when a new frame is ready
    @objc public func notifyFrameReady() {
        guard isRenderingEnabled, textureId >= 0 else { return }
        textureRegistry?.textureFrameAvailable(textureId)
    }
    
    /// Get the Metal texture from current CVPixelBuffer (for native rendering)
    @objc public func getMetalTexture() -> MTLTexture? {
        guard let buffer = pixelBuffer,
              let cache = textureCache else {
            return nil
        }
        
        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            buffer,
            nil,
            .bgra8Unorm,
            surfaceWidth,
            surfaceHeight,
            0,
            &cvMetalTexture
        )
        
        guard status == kCVReturnSuccess, let metalTexture = cvMetalTexture else {
            NSLog("[AgusMapsFlutter] Failed to create Metal texture: %d", status)
            return nil
        }
        
        return CVMetalTextureGetTexture(metalTexture)
    }
    
    // MARK: - Native Bridge (C FFI)
    
    private func nativeSetSurface(textureId: Int64, width: Int32, height: Int32, density: Float) {
        guard let buffer = pixelBuffer else {
            NSLog("[AgusMapsFlutter] nativeSetSurface: no pixel buffer available")
            return
        }
        
        // Call the native C function to set up the rendering surface
        agus_native_set_surface(textureId, buffer, width, height, density)
        
        NSLog("[AgusMapsFlutter] nativeSetSurface complete: texture=%lld, %dx%d, density=%.2f",
              textureId, width, height, density)
    }
    
    private func nativeOnSizeChanged(width: Int32, height: Int32) {
        agus_native_on_size_changed(width, height)
    }
    
    private func nativeOnSurfaceDestroyed() {
        agus_native_on_surface_destroyed()
    }
    
    // MARK: - Helpers
    
    private func lookupKeyForAsset(_ asset: String) -> String {
        // Use Flutter's built-in asset key lookup
        return FlutterDartProject.lookupKey(forAsset: asset)
    }
}

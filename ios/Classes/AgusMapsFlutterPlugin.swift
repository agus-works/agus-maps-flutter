import Flutter
import UIKit
import Metal
import CoreVideo

/// AgusMapsFlutterPlugin - Flutter plugin for CoMaps rendering on iOS
///
/// This plugin implements:
/// - FlutterPlugin for Pigeon messaging
/// - FlutterTexture for zero-copy GPU texture sharing via CVPixelBuffer
///
/// Architecture:
/// 1. Flutter requests a map surface via Pigeon
/// 2. Plugin creates CVPixelBuffer backed by IOSurface (Metal-compatible)
/// 3. Native CoMaps engine renders to MTLTexture derived from CVPixelBuffer
/// 4. Flutter samples the texture directly (zero-copy via IOSurface)
///
/// Note: @objc(AgusMapsFlutterPlugin) gives this class a stable Objective-C name
/// that native code can use with NSClassFromString, avoiding Swift name mangling.
@objc(AgusMapsFlutterPlugin)
public class AgusMapsFlutterPlugin: NSObject, FlutterPlugin, FlutterTexture, AgusMapsHostApi {
    
    // MARK: - Shared Instance for native callbacks
    
    /// Shared instance for native code to notify when frames are ready
    private static weak var sharedInstance: AgusMapsFlutterPlugin?
    
    // Debug: count static method calls
    private static var staticFrameCount: Int = 0
    
    /// Called by native code when a frame is ready
    @objc public static func notifyFrameReadyFromNative() {
        staticFrameCount += 1
        if staticFrameCount <= 5 || staticFrameCount % 60 == 0 {
            NSLog("[AgusMapsFlutter] Swift notifyFrameReadyFromNative called (count=%d, hasInstance=%@)", 
                  staticFrameCount, sharedInstance != nil ? "YES" : "NO")
        }
        DispatchQueue.main.async {
            sharedInstance?.notifyFrameReady()
        }
    }
    
    // MARK: - Properties
    
    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    private var flutterApi: AgusMapsFlutterApi?
    private var mapReadySent: Bool = false
    
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
        let instance = AgusMapsFlutterPlugin()
        instance.textureRegistry = registrar.textures()
        instance.density = UIScreen.main.scale
        instance.flutterApi = AgusMapsFlutterApi(binaryMessenger: registrar.messenger())
        
        // Store shared instance for native callbacks
        AgusMapsFlutterPlugin.sharedInstance = instance
        
        // Initialize Metal device
        instance.metalDevice = MTLCreateSystemDefaultDevice()
        if instance.metalDevice == nil {
            NSLog("[AgusMapsFlutter] Warning: Metal device not available")
        }
        
        AgusMapsHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        
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
    
    // MARK: - Pigeon Host API

    private func stringFromC(_ value: UnsafePointer<CChar>?) -> String {
        guard let value else {
            return ""
        }
        return String(cString: value)
    }

    private func optionalStringFromC(_ value: UnsafePointer<CChar>?) -> String? {
        guard let value else {
            return nil
        }
        return String(cString: value)
    }

    private func makePlacePageData(from native: UnsafePointer<AgusPlacePageData>) -> PlacePageData {
        let featureId = PlacePageFeatureId(
            mwmName: stringFromC(native.pointee.feature_id.mwm_name),
            mwmVersion: native.pointee.feature_id.mwm_version,
            index: native.pointee.feature_id.index
        )

        let coordinates = PlacePageCoordinates(
            decimal: optionalStringFromC(native.pointee.coordinates.decimal),
            dms: optionalStringFromC(native.pointee.coordinates.dms),
            osm: optionalStringFromC(native.pointee.coordinates.osm),
            olc: optionalStringFromC(native.pointee.coordinates.olc),
            utm: optionalStringFromC(native.pointee.coordinates.utm),
            mgrs: optionalStringFromC(native.pointee.coordinates.mgrs)
        )

        var rawTypes: [String] = []
        if let rawTypesPtr = native.pointee.raw_types {
            for index in 0..<Int(native.pointee.raw_types_count) {
                if let value = rawTypesPtr.advanced(by: index).pointee {
                    rawTypes.append(String(cString: value))
                }
            }
        }

        var metadata: [PlacePageIntMetadataEntry] = []
        if let metadataPtr = native.pointee.metadata {
            for index in 0..<Int(native.pointee.metadata_count) {
                let entry = metadataPtr.advanced(by: index).pointee
                metadata.append(
                    PlacePageIntMetadataEntry(
                        key: entry.key,
                        value: stringFromC(entry.value)
                    )
                )
            }
        }

        var metadataTags: [PlacePageStringMetadataEntry] = []
        if let metadataTagsPtr = native.pointee.metadata_tags {
            for index in 0..<Int(native.pointee.metadata_tags_count) {
                let entry = metadataTagsPtr.advanced(by: index).pointee
                metadataTags.append(
                    PlacePageStringMetadataEntry(
                        key: stringFromC(entry.key),
                        value: stringFromC(entry.value)
                    )
                )
            }
        }

        let bookmarkId: Int64? = native.pointee.has_bookmark_id != 0
            ? native.pointee.bookmark_id
            : nil
        let bookmarkCategoryId: Int64? = native.pointee.has_bookmark_category_id != 0
            ? native.pointee.bookmark_category_id
            : nil
        let trackId: Int64? = native.pointee.has_track_id != 0
            ? native.pointee.track_id
            : nil

        return PlacePageData(
            featureId: featureId,
            objectType: Int64(native.pointee.object_type),
            openingMode: Int64(native.pointee.opening_mode),
            title: stringFromC(native.pointee.title),
            secondaryTitle: stringFromC(native.pointee.secondary_title),
            subtitle: stringFromC(native.pointee.subtitle),
            address: stringFromC(native.pointee.address),
            lat: native.pointee.lat,
            lon: native.pointee.lon,
            wikiDescriptionHtml: stringFromC(native.pointee.wiki_description_html),
            roadType: Int64(native.pointee.road_type),
            isRoutePoint: native.pointee.is_route_point != 0,
            coordinates: coordinates,
            rawTypes: rawTypes,
            metadata: metadata,
            metadataTags: metadataTags,
            bookmarkId: bookmarkId,
            bookmarkCategoryId: bookmarkCategoryId,
            trackId: trackId
        )
    }

    func extractMap(assetPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let extractedPath = try self.extractMapAsset(assetPath: assetPath)
                DispatchQueue.main.async {
                    completion(.success(extractedPath))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(PigeonError(code: "EXTRACTION_FAILED", message: error.localizedDescription, details: nil)))
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
    
    func extractDataFiles(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dataPath = try self.extractDataFiles()
                DispatchQueue.main.async {
                    completion(.success(dataPath))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(PigeonError(code: "EXTRACTION_FAILED", message: error.localizedDescription, details: nil)))
                }
            }
        }
    }

    func getApkPath(completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success(Bundle.main.resourcePath ?? ""))
    }

    func getCurrentPlacePage(completion: @escaping (Result<PlacePageData?, Error>) -> Void) {
        guard comaps_place_page_has_data() != 0 else {
            completion(.success(nil))
            return
        }
        guard let nativeData = comaps_place_page_copy() else {
            completion(.success(nil))
            return
        }
        let placePage = makePlacePageData(from: UnsafePointer(nativeData))
        comaps_place_page_free(nativeData)
        completion(.success(placePage))
    }

    func clearPlacePageSelection(completion: @escaping (Result<Bool, Error>) -> Void) {
        comaps_place_page_clear_selection()
        completion(.success(true))
    }
    
    private func extractDataFiles() throws -> String {
        NSLog("[AgusMapsFlutter] Extracting CoMaps data files...")
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let markerFile = documentsDir.appendingPathComponent(".comaps_data_extracted")
        
        // Essential files that must exist for CoMaps to work
        let essentialFiles = [
            "classificator.txt",
            "types.txt", 
            "categories.txt",
            "visibility.txt",
            "symbols/xxhdpi/light/symbols.sdf",  // Symbol textures required for rendering
            "symbols/xxhdpi/dark/symbols.sdf",
            "localized_types/en.lproj/LocalizableTypes.strings"  // Localized POI type names
        ]
        
        // Check if already extracted AND essential files exist
        var needsExtraction = !FileManager.default.fileExists(atPath: markerFile.path)
        if !needsExtraction {
            // Verify essential files exist
            for file in essentialFiles {
                let filePath = documentsDir.appendingPathComponent(file).path
                if !FileManager.default.fileExists(atPath: filePath) {
                    NSLog("[AgusMapsFlutter] Essential file missing: %@, forcing re-extraction", file)
                    needsExtraction = true
                    // Remove marker to force full re-extraction
                    try? FileManager.default.removeItem(atPath: markerFile.path)
                    break
                }
            }
        }
        
        if !needsExtraction {
            NSLog("[AgusMapsFlutter] Data already extracted at: %@", documentsDir.path)
            return documentsDir.path
        }
        
        // Extract data files from bundle's comaps_data directory
        let dataAssetPath = lookupKeyForAsset("assets/comaps_data")
        if let bundleDataPath = Bundle.main.resourcePath?.appending("/\(dataAssetPath)"),
           FileManager.default.fileExists(atPath: bundleDataPath) {
            NSLog("[AgusMapsFlutter] Extracting from bundle path: %@", bundleDataPath)
            try extractDirectory(from: bundleDataPath, to: documentsDir.path)
        } else {
            NSLog("[AgusMapsFlutter] WARNING: Bundle data path not found!")
        }
        
        // Verify extraction was successful
        for file in essentialFiles {
            let filePath = documentsDir.appendingPathComponent(file).path
            if !FileManager.default.fileExists(atPath: filePath) {
                NSLog("[AgusMapsFlutter] WARNING: Essential file still missing after extraction: %@", file)
            } else {
                NSLog("[AgusMapsFlutter] Verified: %@", file)
            }
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
    
    func createMapSurface(request: CreateMapSurfaceRequest, completion: @escaping (Result<Int64, Error>) -> Void) {
        if let densityArg = request.density, densityArg > 0 {
            density = CGFloat(densityArg)
        }

        var width = Int(request.width ?? 0)
        var height = Int(request.height ?? 0)

        if width <= 0 || height <= 0 {
            let screenSize = UIScreen.main.bounds.size
            let screenScale = UIScreen.main.scale
            width = Int(screenSize.width * screenScale)
            height = Int(screenSize.height * screenScale)
        }

        surfaceWidth = width
        surfaceHeight = height
        mapReadySent = false

        NSLog("[AgusMapsFlutter] createMapSurface: %dx%d density=%.2f", width, height, density)

        do {
            try createPixelBuffer(width: width, height: height)

            guard let registry = textureRegistry else {
                completion(.failure(PigeonError(code: "NO_REGISTRY", message: "Texture registry not available", details: nil)))
                return
            }

            textureId = registry.register(self)
            isRenderingEnabled = true

            nativeSetSurface(textureId: textureId, width: Int32(width), height: Int32(height), density: Float(density))

            NSLog("[AgusMapsFlutter] Texture registered: id=%lld", textureId)
            completion(.success(textureId))
            sendRenderStateChanged(state: .active, surfaceId: textureId)
        } catch {
            completion(.failure(PigeonError(code: "CREATE_FAILED", message: error.localizedDescription, details: nil)))
        }
    }

    func resizeMapSurface(request: ResizeMapSurfaceRequest, completion: @escaping (Result<Bool, Error>) -> Void) {
        let width = Int(request.width)
        let height = Int(request.height)
        guard width > 0, height > 0 else {
            completion(.failure(PigeonError(code: "INVALID_ARGUMENT", message: "Valid width and height required", details: nil)))
            return
        }

        let sizeUnchanged = width == surfaceWidth && height == surfaceHeight

        if let densityArg = request.density {
            let newDensity = CGFloat(densityArg)
            if newDensity > 0 && abs(newDensity - density) > .ulpOfOne {
                density = newDensity
                nativeSetVisualScale(density: Float(newDensity))
                NSLog("[AgusMapsFlutter] Updated visual scale: %.2f", newDensity)
            }
        }

        if sizeUnchanged {
            completion(.success(true))
            return
        }

        surfaceWidth = width
        surfaceHeight = height

        do {
            try createPixelBuffer(width: width, height: height)
            if let buffer = pixelBuffer {
                nativeUpdateSurface(pixelBuffer: buffer, width: Int32(width), height: Int32(height))
            }
            textureRegistry?.textureFrameAvailable(textureId)
            completion(.success(true))
        } catch {
            completion(.failure(PigeonError(code: "RESIZE_FAILED", message: error.localizedDescription, details: nil)))
        }
    }

    func destroyMapSurface(completion: @escaping (Result<Bool, Error>) -> Void) {
        cleanupTexture()
        sendRenderStateChanged(state: .idle, surfaceId: nil)
        completion(.success(true))
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
        mapReadySent = false
        
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
    
    // Debug: count instance frame notifications
    private var instanceFrameCount: Int = 0
    
    /// Called by native code when a new frame is ready
    @objc public func notifyFrameReady() {
        instanceFrameCount += 1
        if instanceFrameCount <= 5 || instanceFrameCount % 60 == 0 {
            NSLog("[AgusMapsFlutter] Swift notifyFrameReady instance method (count=%d, enabled=%@, textureId=%lld)", 
                  instanceFrameCount, isRenderingEnabled ? "YES" : "NO", textureId)
        }
        guard isRenderingEnabled, textureId >= 0 else { return }
        textureRegistry?.textureFrameAvailable(textureId)
        if !mapReadySent {
            mapReadySent = true
            sendMapReady(surfaceId: textureId)
        }
    }

    private func sendMapReady(surfaceId: Int64) {
        flutterApi?.onMapReady(surfaceId: surfaceId) { result in
            if case .failure(let error) = result {
                NSLog("[AgusMapsFlutter] onMapReady failed: %@", error.localizedDescription)
            }
        }
    }

    private func sendRenderStateChanged(state: RenderState, surfaceId: Int64?) {
        flutterApi?.onRenderStateChanged(state: state, surfaceId: surfaceId) { result in
            if case .failure(let error) = result {
                NSLog("[AgusMapsFlutter] onRenderStateChanged failed: %@", error.localizedDescription)
            }
        }
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

    private func nativeUpdateSurface(pixelBuffer: CVPixelBuffer, width: Int32, height: Int32) {
        agus_native_update_surface(pixelBuffer, width, height)
    }

    private func nativeSetVisualScale(density: Float) {
        agus_native_set_visual_scale(density)
    }
    
    // MARK: - Helpers
    
    private func lookupKeyForAsset(_ asset: String) -> String {
        // Use Flutter's built-in asset key lookup
        return FlutterDartProject.lookupKey(forAsset: asset)
    }
}

# **Architectural Blueprint for comaps\_widget: A High-Performance, Zero-Copy Geospatial Rendering Engine for Flutter**

## **1\. Introduction: The Imperative for a Unified High-Performance Geospatial Layer**

The architecture of modern mobile Geographic Information Systems (GIS) sits at a precipice between two diverging paradigms: the highly optimized, "close-to-the-metal" efficiency of legacy C++ engines, and the rapid, declarative UI composition offered by modern frameworks like Flutter. Historically, developers have been forced to choose between the raw performance of native implementations—exemplified by the Organic Maps (formerly MAPS.ME) project—and the cross-platform flexibility of managed codebases. This report articulates a comprehensive architectural strategy to bridge this divide. It proposes the creation of comaps\_widget, a cross-platform Flutter widget that encapsulates the rendering capabilities of CoMaps (a community-driven fork of Organic Maps) into a reusable, highly efficient rendering component targeting Linux, macOS, Windows, iOS, and Android.

The central thesis of this architectural proposal is that the "rigid dichotomy" between managed UI frameworks and native performance is a solvable engineering challenge.1 By leveraging the Foreign Function Interface (FFI) capabilities of Dart and the texture-sharing primitives of modern Graphics Processing Units (GPUs), it is possible to architect a system where the "heavy lifting" of geospatial rendering—specifically the tessellation of vector data and the management of large-scale binary assets—remains in the unmanaged C++ heap, while the orchestration and user interaction logic reside in the flexible Dart environment. This approach prioritizes the constraint of "zero-copy" data persistence, a critical requirement for maintaining 60 frames-per-second (FPS) performance on resource-constrained devices, by ensuring that map data flows from disk storage to the GPU vertex shader with negligible CPU intervention and no intermediate allocation in the Dart virtual machine.1

This report serves as a definitive guide for systems engineers and GIS architects. It deconstructs the legacy "Drape" engine used by Organic Maps, analyzes the proprietary MWM binary format that powers its efficiency, and formulates a platform-specific implementation strategy for embedding this engine into the Flutter rendering pipeline without the overhead of traditional PlatformView composition.

### **1.1 The Evolution of the "Monolithic Native" Paradigm**

To understand the necessity of the comaps\_widget, one must first analyze the incumbent architecture it seeks to wrap. Organic Maps represents the pinnacle of the "Monolithic Native" architecture.1 Unlike modern modular libraries such as Mapbox GL Native, which were designed from the outset to be consumed as SDKs, Organic Maps (and its predecessor MapsWithMe) was built as a tightly coupled application where the rendering engine, data storage, routing logic, and user interface are intertwined in a massive C++ codebase.1

This monolithic design was not accidental; it was a deliberate choice to maximize performance on the hardware of 2011\. By handling every aspect of the map lifecycle in C++—from file I/O using mmap to direct OpenGL ES draw calls—the original developers minimized the "instruction cache miss" penalties and memory bandwidth saturation that plagued early mobile Java/Objective-C bridges. The "Drape" engine, the rendering heart of Organic Maps, does not merely draw tiles; it manages a complex scene graph, handles text layout using glyph atlases, and performs real-time triangulation of vector geometry.1

However, the rigidity of this architecture has become a liability in the modern era of cross-platform development. The fork of Organic Maps into CoMaps was driven by governance and community concerns, but it also presents a unique opportunity to refactor the technical debt of the monolith.2 The community's desire for transparency and rapid feature iteration aligns with the proposal to decouple the rendering core from the application logic. By isolating the Drape engine, we not only create a powerful widget for Flutter but also potentially future-proof the core rendering technology of the CoMaps project itself, allowing it to be used in headless environments or other UI frameworks.4

### **1.2 The "Zero-Copy" Mandate and Performance on Slow Devices**

The specific requirement to support "slow devices" mandates a strict adherence to the "Zero-Copy" principle. In traditional Flutter map implementations (e.g., flutter\_map), data undergoes a costly transformation lifecycle: it is read from disk into a Dart Uint8List, decoded into Dart objects (Points, Polygons), transformed for the screen, and then marshaled to the GPU via the Skia canvas. This "copy-transform-upload" loop creates massive pressure on the Garbage Collector (GC), leading to the characteristic "jank" seen in pure Dart map implementations on low-end Android devices.1

The proposed comaps\_widget bypasses this entirely. By utilizing the MWM format's design as a memory-mapped database, the C++ engine treats the file on disk as if it were a heap of valid C++ structures.1 The OS kernel manages the paging of data from flash storage to RAM. When the renderer needs to draw a road, it simply points to the memory address where the road's geometry resides. The Dart layer never touches this data. It merely passes a file path string to the C++ engine. This architecture ensures that the memory footprint of the map data in the Dart VM is effectively zero, regardless of the map size, preserving RAM for the Flutter UI and application logic.1

## **2\. Deconstructing the CoMaps Engine: The "Drape" Core**

To build a wrapper, we must first rigorously understand the internal mechanics of the subject. The rendering engine within Organic Maps/CoMaps is internally referred to as "Drape".1 It is not a general-purpose game engine, nor is it a standard tile rasterizer. It is a specialized vector visualization engine optimized for the cartographic domain.

### **2.1 The Drape Architecture: Frontend vs. Backend**

Drape operates on a threaded architecture that separates the generation of render commands from their execution. This split is fundamental to its performance and must be preserved in the Flutter integration.

* **The Frontend:** This logic runs on the main thread (in the original native app) or a dedicated worker thread. It processes the scene graph, determines which map features are currently visible based on the camera frustum, and generates "RenderBuckets".1 A RenderBucket is a batch of geometry (triangles) and state changes (texture binds, shader uniforms) required to draw a specific layer of the map (e.g., water, roads, text labels).  
* **The Backend:** This logic runs on a dedicated render thread. It consumes the RenderBuckets generated by the frontend and executes the actual graphics API calls (OpenGL ES, Vulkan, or Metal) to draw them to the framebuffer.1

In our comaps\_widget architecture, mapping these threads to the Flutter threading model is critical. We cannot run the Drape Frontend on the Flutter UI thread, as the heavy tessellation logic (converting vector splines into triangles) would block the Dart event loop, causing frame drops. Instead, the comaps\_widget must spawn a background Isolate or a native thread pool to host the Drape Frontend, while the Drape Backend runs on a thread coordinated with the Flutter Raster thread.1

### **2.2 The MWM Data Format: A Binary Database**

The efficiency of CoMaps is inextricably linked to its data format, MWM (MapsWithMe). Unlike interoperable formats like GeoJSON, KML, or even Vector Tiles (MVT/PBF), MWM is a custom binary container designed for random access.1

* **Tag-Length-Value (TLV) Structure:** The file is organized into sections (Tags) such as geom (geometry), idx (spatial index), trg (pre-tessellated triangles), and search (string tries).1  
* **Variable-Byte Encoding (Varints):** To minimize disk footprint, integer coordinates are delta-encoded and compressed using ULEB128 varints. A coordinate sequence for a road might store the absolute position of the first point, followed by small integers representing the offset to subsequent points. This compression allows gigabytes of OSM data to fit on a mobile device.1  
* **Quantization:** Coordinates are fixed-point integers, not floating-point numbers. The engine converts these to screen-space floating-point coordinates only at the last possible moment in the vertex shader, preserving precision and reducing memory usage.1

The implications for comaps\_widget are clear: we must not attempt to parse MWM files in Dart. The logic for traversing the R-Tree spatial index, decoding varints, and generating geometry is complex and highly optimized in C++. Any attempt to replicate this in Dart would be slower and prone to errors. The widget must treat MWM files as opaque blobs managed entirely by the C++ native library.1

### **2.3 The "Framework" Facade**

The entry point to the C++ core is the Framework class (located in map/framework.cpp). In the existing Organic Maps application, this class acts as the central coordinator.3 It initializes the DrapeEngine, manages the Storage subsystem (for downloading and updating maps), and handles routing and search requests.

Currently, the Framework class is tightly coupled to the platform-specific application lifecycles. On Android, it interacts with JNI to receive surfaceCreated and surfaceChanged events from the SurfaceView.9 On iOS, it interacts with Objective-C++ wrappers to bind to a CAEAGLLayer or CAMetalLayer.11

**Architectural Pivot:** To create comaps\_widget, we must refactor or wrap the Framework class to accept a generic "Render Context" rather than a specific platform window handle. We need to create a "Headless Framework" variant that can be driven by an external API (our FFI boundary) rather than the internal event loop of a standalone application.4 This allows the Flutter widget to manually trigger initialization, resizing, and rendering cycles, inverting the control flow.

## **3\. High-Level Architecture: The Texture-Centric Model**

The proposed solution rejects the PlatformView (Hybrid Composition) approach often used for map SDKs. While PlatformView allows embedding a native AndroidView or UIView into the Flutter hierarchy, it introduces significant performance overhead due to the synchronization required between the Flutter rasterizer and the native view compositor. It also suffers from "airspace" issues (rendering overlays on top of the map) and gesture ambiguity.6

Instead, comaps\_widget will utilize a **Texture-Centric Architecture**. In this model, the native C++ engine renders into an offscreen GPU buffer (a texture). This texture ID is passed to Flutter, which renders it as a simple quad within its own Skia/Impeller scene graph. This approach offers the highest possible performance, true zero-copy composition (as the texture stays on the GPU), and perfect integration with Flutter's widget tree (allowing the map to be rotated, scaled, or covered by other Flutter widgets without limitations).12

### **3.1 The Tri-Layer Stack**

The architecture is composed of three distinct layers, each with a specific responsibility:

1. **The Dart Frontend (The Widget):**  
   * **Responsibility:** State management, gesture detection, and API surface.  
   * **Components:** ComapsWidget (StatefulWidget), ComapsController (API), GestureDetector (Input).  
   * **Mechanism:** It captures touch events (pan, zoom, tap) and forwards them to the C++ engine via FFI. It listens for frame updates from the C++ engine to trigger Texture repaints.  
2. **The FFI Interop Layer (The Bridge):**  
   * **Responsibility:** Marshaling data between the Dart VM and the C++ heap.  
   * **Components:** A C-compatible header (comaps\_c\_api.h) and a shared library (libcomaps\_ffi.so/dylib/dll).  
   * **Mechanism:** Since Dart FFI cannot directly interact with C++ classes (due to vtable ABI complexity and name mangling), this layer exposes a simplified C API that wraps the C++ Framework methods.15  
3. **The Native Backend (The Engine):**  
   * **Responsibility:** Data loading, logic processing, and GPU rendering.  
   * **Components:** The drape\_frontend, drape, indexer, and platform modules from the CoMaps core.  
   * **Mechanism:** This layer runs the Drape engine. It creates an OpenGL/Vulkan/Metal context that shares resources with the Flutter renderer, allowing the output texture to be consumed directly by Flutter.13

### **3.2 The Rendering Loop Synchronization**

A critical aspect of this architecture is the synchronization of render loops. Flutter operates on a "VSync" driven loop. The C++ engine in Organic Maps also has its own internal loop.

* **Naive Approach (Bad):** Letting the C++ engine render freely on its own thread. This leads to desynchronization, tearing, and battery drain as the engine might render frames that Flutter is not ready to display.  
* **Proposed Approach (Good):** **Demand-Driven Rendering.** The C++ engine's render loop should be "paused" by default.  
  1. When an interaction occurs (e.g., user pans the map in Flutter), the Dart side calls ComapsController.moveCamera().  
  2. This FFI call updates the camera state in C++ and sets a "dirty" flag.  
  3. The C++ engine performs the necessary calculations (tessellation) on a worker thread.  
  4. When the frame is ready, the C++ engine invokes a callback to Dart via NativePort (SendPort).  
  5. Dart receives the signal and calls setState() (or notifies a Texture listener) to mark the widget as needing a repaint.  
  6. During Flutter's paint phase, the Texture widget displays the updated GPU buffer.

This mechanism ensures that we only render when necessary, adhering to the "works on slow devices" requirement by minimizing battery and CPU usage.18

## **4\. Platform-Specific Implementation Strategy**

The challenge of cross-platform development is that "Zero-Copy" means different things on different operating systems. The mechanism to share a texture between C++ and Flutter varies significantly. The comaps\_widget must implement a "Rendering Backend Abstraction" to handle these differences.

### **4.1 Android: The EGL SurfaceTexture Bridge**

On Android, the integration is facilitated by the SurfaceTexture API, which effectively acts as a bridge between an OpenGL ES producer (our C++ engine) and a consumer (Flutter).20

* **Flutter Side:** We use TextureRegistry.createSurfaceProducer() (the new Android API replacing createSurfaceTexture) to generate a SurfaceProducer.20 This gives us a unique texture ID and a Surface object.  
* **JNI Layer:** We must pass this Surface object from Java/Kotlin to the C++ layer using JNI. While the prompt requests C++, Android's Surface API requires a minimal JNI handshake to convert the Java Surface object into a native ANativeWindow\* handle.22  
* **C++ Side:** The Drape engine treats this ANativeWindow\* as its display window. It creates an EGLSurface tied to this window:  
  C++  
  EGLSurface surface \= eglCreateWindowSurface(display, config, native\_window, attribs);

* **Zero-Copy Mechanism:** When Drape issues glSwapBuffers (or eglSwapBuffers), the GPU driver flips the buffer within the SurfaceTexture. Flutter, holding the texture ID corresponding to that SurfaceTexture, can then sample from it immediately in its next render pass. The data stays on the GPU; no pixels are copied to CPU memory.13

**Critical Implementation Note:** The comaps\_widget must strictly manage the EGL context. To ensure resources (like textures for map icons) can be shared if needed, it is beneficial to configure the C++ EGL context to share with the Flutter EGL context, although for a pure output texture, isolated contexts are often more stable to prevent GL state corruption.13

### **4.2 iOS: The CVPixelBuffer and Metal Interop**

iOS requires a more modern approach, as OpenGL ES is deprecated. Flutter on iOS primarily uses the Metal rendering backend.

* **Flutter Side:** The widget requests a texture from the FlutterTextureRegistry.  
* **Native Side (Objective-C++):** We implement the FlutterTexture protocol. The core method is copyPixelBuffer.  
* **Zero-Copy Mechanism:** We utilize CVPixelBuffer backed by an IOSurface. An IOSurface is a system-level object that represents a chunk of GPU memory accessible by different processes or graphics APIs (Metal, OpenGL, CoreAnimation).24  
  1. Allocate a CVPixelBuffer with the kCVPixelBufferMetalCompatibilityKey flag.  
  2. Create a Metal texture (id\<MTLTexture\>) from this pixel buffer using CVMetalTextureCacheCreateTextureFromImage.  
  3. The CoMaps C++ engine (using its Metal backend) renders into this MTLTexture.  
  4. When Flutter calls copyPixelBuffer, we return the CVPixelBuffer.  
  5. Flutter's engine (Impeller/Skia) reads from this buffer directly.

This pipeline ensures that the high-frequency map rendering happens entirely in GPU memory, satisfying the performance requirements.24

### **4.3 Linux: GTK and GLX/EGL**

On Linux, Flutter embeds inside a GTK window. The flutter\_linux embedder provides a FlTextureGL API.26

* **Mechanism:** We subclass FlTextureGL. The critical method to override is populate.  
* **C++ Side:** The engine renders to a Framebuffer Object (FBO). This FBO is backed by a standard OpenGL texture (GLuint).  
* **Integration:**  
  C  
  gboolean my\_texture\_gl\_populate(FlTextureGL \*texture, uint32\_t \*target, uint32\_t \*name,...) {  
      // C++ engine has already rendered to texture\_id  
      \*target \= GL\_TEXTURE\_2D;  
      \*name \= engine-\>getTextureId(); // The texture handle  
      return TRUE;  
  }

* **Context Sharing:** Crucially, the C++ engine must share the OpenGL context with the GDK/GTK context used by Flutter. This is usually handled by gdk\_window\_create\_gl\_context, and the C++ engine must accept an external context handle during initialization rather than creating its own isolated context.26

### **4.4 Windows: WGL/OpenGL with D3D11 Texture Sharing (Implemented)**

Windows presented unique challenges for Flutter integration. Unlike iOS/macOS (IOSurface) and Android (SurfaceTexture), there is no native zero-copy path between OpenGL and the D3D11-based Flutter renderer.

> **Architecture Note:** Only x86_64 is currently supported. ARM64 Windows support is theoretically possible but untested due to lack of development hardware.

**Implemented Solution:** Native WGL/OpenGL with CPU-mediated D3D11 texture sharing.

* **Why not ANGLE?** While the original plan suggested using ANGLE (as noted in historical documentation), the actual implementation uses native WGL/OpenGL. This approach was chosen because:
  1. CoMaps' Drape engine is already optimized for desktop OpenGL
  2. WGL provides stable, driver-native OpenGL on Windows
  3. ANGLE introduces additional translation overhead

* **The Bridge Mechanism:**
  1. **WGL Context Creation:** A hidden window provides the device context for WGL. Two OpenGL contexts are created (draw and upload) with shared resources via `wglShareLists()`.
  2. **Offscreen Rendering:** CoMaps renders to an OpenGL Framebuffer Object (FBO) backed by a GL texture and depth/stencil renderbuffer.
  3. **CPU-Mediated Copy:** After each frame, `glReadPixels()` reads the FBO content into a CPU buffer.
  4. **D3D11 Staging Texture:** The CPU buffer is written to a D3D11 staging texture (with RGBA→BGRA conversion and Y-flip).
  5. **Shared Texture:** The staging texture is copied to a D3D11 shared texture exposed via DXGI handle.
  6. **Flutter Integration:** Flutter samples the shared texture via `FlutterDesktopGpuSurfaceDescriptor`.

* **Performance Characteristics:**
  ```
  OpenGL FBO → glReadPixels (GPU→CPU) → RGBA→BGRA + Y-flip → D3D11 Staging → D3D11 Shared
                    ~2-5ms at 1080p           ~1ms CPU              GPU-GPU copy
  ```
  Total overhead: ~3-6ms per frame on modern hardware, acceptable for 60fps.

* **NOT Zero-Copy:** Unlike iOS/macOS/Android, Windows does NOT achieve true zero-copy. The `glReadPixels()` call moves data from GPU to CPU memory. This is a fundamental limitation of the OpenGL/D3D11 interop landscape on Windows without vendor-specific extensions (WGL_NV_DX_interop2 requires NVIDIA GPUs).

* **D3D11 Shared Handle:** The shared texture uses `D3D11_RESOURCE_MISC_SHARED` and exposes a DXGI handle that Flutter can sample directly. This final GPU→Flutter step IS zero-copy.

**Critical Implementation Notes:**
1. The D3D11 shared handle changes on surface resize - the Flutter texture callback must query the current handle dynamically.
2. `glFinish()` must be called before reading pixels to ensure rendering is complete.
3. `m_d3dContext->Flush()` must be called after D3D11 copy to ensure Flutter sees updated data.
* **Zero-Copy:** By unifying on the ANGLE layer, the texture remains a DirectX resource under the hood, accessible to both the map engine and Flutter's Skia renderer without CPU readback.

### **4.5 macOS: IOSurface and Metal**

The macOS implementation mirrors iOS but often involves the FlutterTexture protocol in a macOS-specific runner. The CVPixelBuffer backed by IOSurface remains the gold standard for zero-copy interop on Apple Silicon and Intel Macs.12

## **5\. The FFI Bridge Design: Replacing JNI**

The original Organic Maps architecture relies heavily on JNI (Java Native Interface) for Android and Objective-C++ for iOS to communicate between the UI and the Engine. comaps\_widget replaces these with a uniform C API that Dart can call directly via dart:ffi. This reduces overhead (FFI is generally faster than JNI) and unifies the codebase.15

### **5.1 The C API Surface (comaps\_c\_api.h)**

We must define a C header that acts as the boundary.

| Function Category | Function Signature | Description |
| :---- | :---- | :---- |
| **Lifecycle** | ComapsHandle comaps\_create(const char\* storage\_path) | Initializes the Framework instance. |
|  | void comaps\_destroy(ComapsHandle handle) | Tears down the engine. |
| **Surface** | void comaps\_set\_surface(ComapsHandle h, void\* window, int w, int h) | Passes the native window handle (Android Surface, etc.). |
| **Rendering** | void comaps\_render\_frame(ComapsHandle h) | Triggers a draw call. |
| **Input** | void comaps\_touch(ComapsHandle h, int type, int id, float x, float y) | Forwards pointer events. |
| **Map Control** | void comaps\_load\_map(ComapsHandle h, const char\* mwm\_path) | Loads a map file (zero-copy mmap). |
| **Camera** | void comaps\_set\_view(ComapsHandle h, double lat, double lon, int zoom) | Moves the viewport. |

### **5.2 Memory Management and Safety**

When passing data across this boundary, we must be vigilant.

* **Strings:** Dart strings are UTF-16; C++ expects UTF-8. We must use Utf8.toUtf8() allocators in Dart and ensure the C++ side copies the string if it needs to persist it beyond the function call.15  
* **Structs:** For high-frequency data like touch events, we should pass primitives (ints, floats) directly rather than allocating structs, to avoid the overhead of calloc/free on every frame.15  
* **Thread Safety:** The FFI calls are synchronous on the calling thread. Calls that might block (like comaps\_load\_map which opens a file) must be executed in a Dart Isolate or the C++ implementation must immediately offload the work to its own worker thread and return control.29

## **6\. Implementation Roadmap**

### **Phase 1: Core Decoupling (The "Headless" Engine)**

The first step is to modify the CoMaps C++ source to build as a shared library (libcomaps) without any GUI dependencies (Qt, Android Activity, etc.).

* **Action:** Create a new CMakeLists.txt that defines a library target excluding android/, iphone/, and qt/ directories.  
* **Action:** Refactor map/framework.cpp to remove dependencies on the Android JNI environment. Replace JNI calls for asset loading (fonts, world.mwm) with standard C++ std::filesystem or platform-agnostic file paths passed from Dart.1

### **Phase 2: The FFI Layer**

* **Action:** Implement the comaps\_c\_api.cpp which exposes the extern "C" functions. This file acts as the adapter, instantiating the C++ Framework class and translating C-style calls into C++ method calls.16

### **Phase 3: Platform Bindings**

* **Action:** Implement the platform-specific "glue" code.  
  * *Android:* A small JNI shim to get the ANativeWindow from the Surface.  
  * *iOS/macOS:* An Objective-C++ shim to manage the CVPixelBuffer.  
  * *Linux/Windows:* C++ code to handle the GL context sharing.

### **Phase 4: The Dart Widget**

* **Action:** Create the ComapsWidget in Dart.  
* **Action:** Implement the Texture widget integration.  
* **Action:** Implement GestureDetector logic to translate Flutter ScaleUpdateDetails into the zoom/pan/rotate commands the engine expects.

## **7\. Performance Considerations and "Works on Slow Devices"**

To meet the requirement of working on slow devices, we rely on three pillars:

1. **MWM Efficiency:** By preserving the MWM format, we ensure that map data is not loaded into RAM until needed. The "hot" data (currently visible tiles) resides in the OS page cache. Cold data stays on disk. This is the only way to render a 500MB country map on a device with 2GB of RAM.1  
2. **Vector Tessellation on Worker Threads:** The Drape engine must perform tessellation (math-heavy geometry generation) on background threads. We must ensure the comaps\_widget initialization configures the Drape thread pool correctly for the device's core count (e.g., limiting to 2 worker threads on a quad-core device to leave room for the UI thread).1  
3. **Variable Refresh Rate:** Maps do not need to render at 60 FPS when static. The widget should implement a "demand-driven" loop. If the user is not touching the screen and no animations are playing, the render loop should sleep. This saves massive amounts of battery compared to a game-style infinite loop.18

## **8\. Conclusion**

The creation of comaps\_widget is a sophisticated exercise in systems programming, requiring deep knowledge of both Flutter's embedding API and the legacy C++ architecture of Organic Maps. However, the path is clear. By rejecting the PlatformView shortcut and embracing a Texture-centric, FFI-driven architecture, we can deliver a map widget that offers **native performance** within a cross-platform Flutter codebase.

This architecture satisfies all constraints: it is **cross-platform** (Linux, Win, Mac, Android, iOS), **excludes Web** (due to the lack of mmap), is **zero-copy** (via shared GPU textures and memory-mapped files), and is optimized for **slow devices** (via the MWM database and background tessellation). It transforms CoMaps from a standalone application into a versatile infrastructure component, ready to power the next generation of logistics, travel, and outdoor applications.

## **9\. Appendix: Technical Reference Tables**

### **Table 1: Platform Rendering Backends & Integration Strategy**

| Platform | Flutter Renderer | CoMaps Backend | Integration Mechanism | Context Sharing |
| :---- | :---- | :---- | :---- | :---- |
| **Android** | OpenGL / Vulkan | OpenGL ES 3.0 | SurfaceTexture (Java \-\> JNI \-\> C++) | EGLContext sharing optional; Surface isolation recommended. |
| **iOS** | Metal | Metal / OpenGL | CVPixelBuffer (backed by IOSurface) | Shared via system IOSurface. |
| **Linux** | OpenGL | OpenGL | FlTextureGL (GTK Embedder) | GLX/EGL context sharing required. |
| **Windows** | DirectX 11 (ANGLE) | OpenGL (via ANGLE) | Shared Handle / WGL\_NV\_DX\_interop | Link C++ core against ANGLE libraries. |
| **macOS** | Metal | Metal | CVPixelBuffer (backed by IOSurface) | Shared via system IOSurface. |

### **Table 2: Comparison of Map Data Architectures**

| Feature | GeoJSON / KML | Vector Tiles (MVT) | Organic Maps (MWM) |
| :---- | :---- | :---- | :---- |
| **Storage Format** | Text / XML | Protobuf (Tile based) | Custom Binary Database |
| **Access Method** | Parse entire file to Heap | Parse tile-by-tile | Memory Map (mmap) (Zero-Copy) |
| **Memory Usage** | High (DOM object overhead) | Medium (Tile caching) | Low (OS Kernel Paging) |
| **Performance** | Low (Parsing overhead) | High (Server-side optimized) | Very High (Client-side optimized) |
| **Suitability** | Small datasets overlays | Web & Standard Maps | **Offline, Large-Scale, Low-End Devices** |

### **Table 3: Suggested FFI API Surface (comaps\_c\_api.h)**

| Function Name | Parameters | Purpose |
| :---- | :---- | :---- |
| comaps\_create | const char\* storage\_path | Initialize engine instance. |
| comaps\_load\_mwm | const char\* path | Load map file (Zero-copy). |
| comaps\_resize | int width, int height | Update viewport size. |
| comaps\_touch | int type, int id, float x, float y | Inject input event. |
| comaps\_render | void | Execute single frame render. |
| comaps\_get\_texture\_id | void | Returns GL texture ID / Pointer. |

#### **Works cited**

1. Flutter Zero-Copy Map Engine.pdf  
2. CoMaps emerges as an Organic Maps fork \- LWN.net, accessed December 17, 2025, [https://lwn.net/Articles/1024387/](https://lwn.net/Articles/1024387/)  
3. organicmaps/docs/STRUCTURE.md at master \- GitHub, accessed December 17, 2025, [https://github.com/organicmaps/organicmaps/blob/master/docs/STRUCTURE.md](https://github.com/organicmaps/organicmaps/blob/master/docs/STRUCTURE.md)  
4. Headless Rendering \- Polyscope \- C++, accessed December 17, 2025, [https://polyscope.run/features/headless\_rendering/](https://polyscope.run/features/headless_rendering/)  
5. organicmaps/docs/INSTALL.md at master \- GitHub, accessed December 17, 2025, [https://github.com/organicmaps/organicmaps/blob/master/docs/INSTALL.md](https://github.com/organicmaps/organicmaps/blob/master/docs/INSTALL.md)  
6. Flutter integration with OpenGL like apploica : r/flutterhelp \- Reddit, accessed December 17, 2025, [https://www.reddit.com/r/flutterhelp/comments/1ibhhro/flutter\_integration\_with\_opengl\_like\_apploica/](https://www.reddit.com/r/flutterhelp/comments/1ibhhro/flutter_integration_with_opengl_like_apploica/)  
7. Cross-platform 3D Rendering in Flutter \- Blog, accessed December 17, 2025, [https://blog.mqhamdam.pro/flutter-three-d-crossplatform-rendering/](https://blog.mqhamdam.pro/flutter-three-d-crossplatform-rendering/)  
8. US5379432A \- Object-oriented interface for a procedural operating system \- Google Patents, accessed December 17, 2025, [https://patents.google.com/patent/US5379432A/en](https://patents.google.com/patent/US5379432A/en)  
9. Android Map Rendering Data Flow \- MapLibre Native Developer Documentation, accessed December 17, 2025, [https://maplibre.org/maplibre-native/docs/book/design/android-map-rendering-data-flow.html](https://maplibre.org/maplibre-native/docs/book/design/android-map-rendering-data-flow.html)  
10. android \- surfaceCreated() Never Called \- Stack Overflow, accessed December 17, 2025, [https://stackoverflow.com/questions/6860826/surfacecreated-never-called](https://stackoverflow.com/questions/6860826/surfacecreated-never-called)  
11. Add a map to your iOS app (Objective-C) | Google for Developers, accessed December 17, 2025, [https://developers.google.com/codelabs/maps-platform/maps-platform-101-objc](https://developers.google.com/codelabs/maps-platform/maps-platform-101-objc)  
12. Integrating PlatformView into Flutter (iOS/macOS) | by Chuvak Pavel | Oct, 2025 | Medium, accessed December 17, 2025, [https://medium.com/@chuvak-pavel/integrating-platformview-into-flutter-ios-macos-17bae9e523b8](https://medium.com/@chuvak-pavel/integrating-platformview-into-flutter-ios-macos-17bae9e523b8)  
13. Flutter Analysis and Practice: Same Layer External Texture Rendering \- Alibaba Cloud, accessed December 17, 2025, [https://www.alibabacloud.com/blog/flutter-analysis-and-practice-same-layer-external-texture-rendering\_596580](https://www.alibabacloud.com/blog/flutter-analysis-and-practice-same-layer-external-texture-rendering_596580)  
14. Rendering “External Texture”: A Flutter Optimization Story | by Alibaba Tech \- Medium, accessed December 17, 2025, [https://medium.com/hackernoon/rendering-external-texture-an-flutter-optimization-by-alibaba-c5ed143af747](https://medium.com/hackernoon/rendering-external-texture-an-flutter-optimization-by-alibaba-c5ed143af747)  
15. How To Use Dart FFI For High-Performance Flutter Integrations \- Vibe Studio, accessed December 17, 2025, [https://vibe-studio.ai/insights/how-to-use-dart-ffi-for-high-performance-flutter-integrations](https://vibe-studio.ai/insights/how-to-use-dart-ffi-for-high-performance-flutter-integrations)  
16. C++ internals: mapping from C++ classes and methods to C structs and functions | by EventHelix | Software Design | Medium, accessed December 17, 2025, [https://medium.com/software-design/c-internals-mapping-from-c-classes-and-methods-to-c-structs-and-functions-f4a58c3f7985](https://medium.com/software-design/c-internals-mapping-from-c-classes-and-methods-to-c-structs-and-functions-f4a58c3f7985)  
17. Can I share a external texture between 2 OpenGL contexts, Android \- Stack Overflow, accessed December 17, 2025, [https://stackoverflow.com/questions/31954439/can-i-share-a-external-texture-between-2-opengl-contexts-android](https://stackoverflow.com/questions/31954439/can-i-share-a-external-texture-between-2-opengl-contexts-android)  
18. repeatedly render loop with Qt and OpenGL \- c++ \- Stack Overflow, accessed December 17, 2025, [https://stackoverflow.com/questions/1807857/repeatedly-render-loop-with-qt-and-opengl](https://stackoverflow.com/questions/1807857/repeatedly-render-loop-with-qt-and-opengl)  
19. Is Qt running on a render loop? : r/QtFramework \- Reddit, accessed December 17, 2025, [https://www.reddit.com/r/QtFramework/comments/kf8vj8/is\_qt\_running\_on\_a\_render\_loop/](https://www.reddit.com/r/QtFramework/comments/kf8vj8/is_qt_running_on_a_render_loop/)  
20. New APIs for Android plugins that render to a Surface \- Flutter documentation, accessed December 17, 2025, [https://docs.flutter.dev/release/breaking-changes/android-surface-plugins](https://docs.flutter.dev/release/breaking-changes/android-surface-plugins)  
21. Qt on Android: How to create a zero-copy Android SurfaceTexture QML item | KDAB, accessed December 17, 2025, [https://www.kdab.com/qt-android-create-zero-copy-android-surfacetexture-qml-item/](https://www.kdab.com/qt-android-create-zero-copy-android-surfacetexture-qml-item/)  
22. Diving into JNI: My Messy Adventures With C++ in Android \- DZone, accessed December 17, 2025, [https://dzone.com/articles/diving-into-jni-my-messy-adventures-with-c-in-andr](https://dzone.com/articles/diving-into-jni-my-messy-adventures-with-c-in-andr)  
23. How to call Android framework c++ functions in JNI? \- Stack Overflow, accessed December 17, 2025, [https://stackoverflow.com/questions/20065078/how-to-call-android-framework-c-functions-in-jni](https://stackoverflow.com/questions/20065078/how-to-call-android-framework-c-functions-in-jni)  
24. Combine the power of CoreGraphics and Metal by sharing resource memory \- Medium, accessed December 17, 2025, [https://medium.com/@s1ddok/combine-the-power-of-coregraphics-and-metal-by-sharing-resource-memory-eabb4c1be615](https://medium.com/@s1ddok/combine-the-power-of-coregraphics-and-metal-by-sharing-resource-memory-eabb4c1be615)  
25. yamadapc/flutter\_metal\_texture: Demo metal texture rendering within flutter app \- GitHub, accessed December 17, 2025, [https://github.com/yamadapc/flutter\_metal\_texture](https://github.com/yamadapc/flutter_metal_texture)  
26. Flutter Linux Embedder: \_FlTextureGLClass Struct Reference, accessed December 17, 2025, [https://api.flutter.dev/linux-embedder/struct\_\_\_fl\_texture\_g\_l\_class.html](https://api.flutter.dev/linux-embedder/struct___fl_texture_g_l_class.html)  
27. Native surface or shared texture widget \- Windows \- General \- Flutter Forum, accessed December 17, 2025, [https://forum.itsallwidgets.com/t/native-surface-or-shared-texture-widget-windows/2361](https://forum.itsallwidgets.com/t/native-surface-or-shared-texture-widget-windows/2361)  
28. Using Dart FFI to Communicate with CPP in Flutter \- GeekyAnts, accessed December 17, 2025, [https://geekyants.com/blog/using-dart-ffi-to-communicate-with-cpp-in-flutter](https://geekyants.com/blog/using-dart-ffi-to-communicate-with-cpp-in-flutter)  
29. JNI tips \- NDK \- Android Developers, accessed December 17, 2025, [https://developer.android.com/ndk/guides/jni-tips](https://developer.android.com/ndk/guides/jni-tips)  
30. CMake: How to set up source, library and CMakeLists.txt dependencies? \- Stack Overflow, accessed December 17, 2025, [https://stackoverflow.com/questions/31512485/cmake-how-to-set-up-source-library-and-cmakelists-txt-dependencies](https://stackoverflow.com/questions/31512485/cmake-how-to-set-up-source-library-and-cmakelists-txt-dependencies)

---

## **Appendix A: Development Status and Pending Work**

### **A.1 Current Implementation Status (December 2024)**

#### **Completed**
- ✅ Android JNI bridge layer with OpenGL ES 3.0 rendering
- ✅ EGL context management with shared contexts for multi-threaded rendering
- ✅ JNI-based GuiThread for main thread task dispatch
- ✅ Asset extraction system for CoMaps data files
- ✅ GL function pointer resolution fix for Android (eglGetProcAddress)
- ✅ Directory-based resource loading (Platform and Transliteration)
- ✅ Framework initialization and Drape engine startup
- ✅ Backend and Frontend renderer threads started
- ✅ Frame rendering to Flutter texture via SurfaceProducer
- ✅ Touch/gesture event forwarding to Framework
- ✅ Map viewport resize handling with dynamic surface recreation
- ✅ Flutter Dart API (`AgusMapController`) for map control (setView, moveToLocation)
- ✅ Multitouch gesture support (pan, pinch-to-zoom)

#### **Not Started**
- ⏳ iOS/macOS implementation
- ⏳ Linux/Windows desktop implementation
- ⏳ Search API integration
- ⏳ Routing API integration
- ⏳ POI interaction callbacks
- ⏳ Map download management
- ⏳ Animated camera transitions
- ⏳ Compass and ruler widgets (requires symbols.sdf generation)

### **A.2 CoMaps Submodule Patches**

The `thirdparty/comaps` directory contains a modified checkout of the CoMaps source. The modifications are tracked via patch files in `patches/comaps/`:

| Patch | Description |
|-------|-------------|
| `0001-fix-cmake.patch` | CMake configuration fixes for cross-compilation |
| `0002-platform-directory-resources.patch` | Directory-based resource loading in `platform_android.cpp` |
| `0003-transliteration-directory-resources.patch` | Directory-based ICU data file loading |
| `0004-fix-android-gl-function-pointers.patch` | Android GL function pointer resolution via `eglGetProcAddress` |

**Note:** After cloning the repository, run `./scripts/apply_comaps_patches.sh` to apply these patches to a fresh CoMaps checkout.

### **A.3 Known Issues**

1. **Transliteration Loader Spam**: The ICU data file check logs repeatedly during initialization. This is cosmetic but should be deduplicated.

2. **Missing Transit Colors**: Warning about missing `transit_colors.txt` file. This file is optional and doesn't affect basic map rendering.

3. **Unknown Transit Symbols**: Warnings about unknown transit symbols (tram, bus, ferry, etc.). These are optional icons that don't affect core functionality.

### **A.4 Build Requirements**

- **Android NDK**: r25c or later
- **CMake**: 3.18+
- **Flutter**: 3.x stable channel
- **Android SDK**: API 24+ (minSdk), API 34 (targetSdk)

### **A.5 Testing the Current Implementation**

```bash
# Build and install the example app
cd example
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Launch and monitor logs
adb logcat -c
adb shell am start -n app.agus.maps.agus_maps_flutter_example/.MainActivity
adb logcat | grep -E "(CoMaps|AGUS|drape)"
```

Expected log output showing successful initialization:
```
D CoMaps: Framework(): Classificator initialized
I CoMaps: Visual scale = 2 ; Tile size = 256 ; Resources = xhdpi
I CoMaps: drape_frontend/backend_renderer.cpp: Start routine.
I CoMaps: drape_frontend/frontend_renderer.cpp: Start routine.
I CoMaps: Renderer = Mali-G76 | Api = OpenGLES3 | Version = OpenGL ES 3.2
```
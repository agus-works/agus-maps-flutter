# **Architectural Analysis and Optimization Strategy: Implementing Zero-Copy Memory Pipelines for Agus Maps on Windows**

> [!NOTE]
> **Status: IMPLEMENTED (January 2026)**
> The architecture proposed in this document—specifically Phase 1, 2, and 3 using `WGL_NV_DX_interop`—has been successfully implemented.
> See [doc/IMPLEMENTATION-WIN.md](IMPLEMENTATION-WIN.md) for the live documentation and [doc/RENDER-LOOP.md](RENDER-LOOP.md) for the current architecture diagrams.
> This document is preserved as a historical reference of the design process.

## **Executive Summary**

The proliferation of high-fidelity, cross-platform applications has necessitated a fundamental reevaluation of how rendering pipelines are architected, particularly when bridging disparate graphics technologies on desktop operating systems. This report provides an exhaustive technical analysis of the feasibility and implementation strategy for introducing an efficient, zero-copy memory rendering pipeline with no CPU mediation for the agus-maps-flutter repository on the Windows platform. The core objective is to bypass the traditional, latency-inducing bottlenecks associated with texture transport between the OpenGL-based CoMaps engine and the Direct3D 11-based Flutter Windows engine.

Our extensive review of the current architectural landscape, specifically the interactions between the Windows graphics subsystem, the Flutter embedder API, and the native CoMaps library, confirms that achieving a true zero-copy pipeline is not only possible but essentially required for performance parity with mobile platforms. The analysis identifies the WGL\_NV\_DX\_interop extension, leveraged in conjunction with DirectX Graphics Infrastructure (DXGI) shared handles and Keyed Mutex synchronization, as the definitive mechanism to achieve this goal. By structurally modifying the Windows implementation of agus-maps-flutter to utilize these technologies, developers can effectively eliminate CPU involvement in frame transmission, keeping all pixel data resident in Video Random Access Memory (VRAM) and unlocking native 60 FPS rendering performance.

This document serves as a comprehensive implementation guide and architectural critique, synthesizing insights from analogous high-performance video rendering projects like media\_kit, detailing the specific C++ and Dart interoperability requirements, and providing a roadmap for overcoming the unique "Air Gap" between OpenGL and Direct3D on Windows.

## **1\. Introduction: The Imperative of High-Performance Rendering**

### **1.1 The Cross-Platform Graphics Conundrum**

In the realm of modern application development, the promise of "write once, run anywhere" frameworks like Flutter is frequently tested by the rigid realities of hardware abstraction layers. While Flutter provides a unified API for UI composition, the underlying rendering engines it relies on vary significantly across platforms. On mobile devices (Android and iOS), the rendering pipeline is relatively streamlined due to the ubiquity of OpenGL ES and Metal, which allow for reasonably direct interoperability with native code. However, the Windows platform introduces a distinct layer of complexity that has historically plagued cross-platform graphics developers: the dominance of DirectX.

The agus-maps-flutter repository represents a sophisticated effort to embed the CoMaps (formerly Organic Maps/MAPS.ME) rendering engine into a Flutter application.1 CoMaps is a highly optimized C++ vector map renderer that relies on OpenGL for drawing complex geospatial data, including 3D terrain, vector tiles, and labels.1 This dependency on OpenGL creates a fundamental friction point when deploying to Windows, where the Flutter engine utilizes ANGLE (Almost Native Graphics Layer Engine) to translate its own OpenGL ES instructions into Direct3D 11 calls.3 This translation layer ensures Flutter's broad compatibility across the fragmented Windows hardware ecosystem but inadvertently erects a barrier—an "Air Gap"—between the native plugin's OpenGL context and the Flutter engine's Direct3D surface.

### **1.2 Defining the Performance Bottleneck**

The default mechanism for bridging this gap in many nascent Flutter plugins involves a "pixel buffer" approach. In this scenario, the native engine renders a frame to an off-screen framebuffer. The CPU then intervenes to read this data from the GPU's VRAM into system RAM (using functions like glReadPixels), performs a memory copy to format the data, and then uploads it back to the GPU into a texture that Flutter can display.3

This round-trip journey—VRAM to RAM to VRAM—is antithetical to high-performance rendering. It introduces significant latency, increases power consumption, and, critically, saturates the system's memory bandwidth (PCI-E bus), leading to dropped frames and stuttering during map interactions like panning and zooming. The user's query specifically targets the elimination of this inefficiency, seeking a "zero-copy" solution where "no CPU mediation" occurs.

### **1.3 The Concept of Zero-Copy in Heterogeneous Graphics**

To satisfy the strict requirement of "no CPU mediation," the rendered frame data must never leave the GPU's dedicated video memory. The CPU's role must be relegated strictly to control logic—passing pointers, handling input events, and managing synchronization signals. The pixel data itself must be "teleported" from the producer (CoMaps OpenGL Context) to the consumer (Flutter Direct3D Context) without duplication.

This report establishes that this is achieved not by copying data, but by *aliasing* memory resources. Through specific driver extensions and operating system APIs, a single block of VRAM can be exposed to multiple graphics APIs simultaneously. The OpenGL context "sees" a Renderbuffer, while the Direct3D context "sees" a Texture2D, yet both point to the exact same physical transistors on the graphics card. This architectural tweak is the holy grail of interop performance and is the primary focus of the solution proposed herein.

## **2\. Architectural Analysis of the Windows Graphics Ecosystem**

To implement a robust solution for agus-maps-flutter, one must first understand the hostile terrain of Windows graphics interoperability. The seamless experience users expect relies on a delicate negotiation between legacy OpenGL support and the modern DirectX infrastructure.

### **2.1 The Role of ANGLE and the API Schism**

Flutter on Windows does not natively speak OpenGL in the way a Linux application does. Instead, it relies on Google's ANGLE project to act as a translator. ANGLE implements the OpenGL ES 2.0/3.0 specification by mapping it on top of the system's native graphics API, which on Windows is almost exclusively Direct3D 11\.3

This architecture is robust for standard UI widgets but creates a significant hurdle for native plugins like CoMaps. When agus-maps-flutter initializes the CoMaps engine, that engine creates a standard, hardware-accelerated OpenGL context (WGL). This context is entirely unaware of the ANGLE context Flutter is using. They are effectively two separate islands of rendering execution.

* **Island A (CoMaps):** Rendering vector tiles using standard OpenGL commands to a hidden surface.  
* **Island B (Flutter):** Rendering the application UI using Direct3D 11 (via ANGLE).

Standard OpenGL functions cannot share textures with Direct3D contexts out of the box. A naive implementation forces the developer to bridge these islands using the CPU as a ferry, carrying pixel data back and forth. The "tweak" requested involves building a bridge—a shared memory tunnel—that connects these islands directly at the hardware level.4

### **2.2 The Evolution of Interoperability Extensions**

The industry has long recognized the need for OpenGL and DirectX to coexist. This has led to the development of specific extensions designed to facilitate exactly the kind of zero-copy resource sharing required by agus-maps-flutter.

#### **2.2.1 WGL\_NV\_DX\_interop**

The primary mechanism for this interoperability is the WGL\_NV\_DX\_interop extension (and its updated version WGL\_NV\_DX\_interop2). Despite the "NV" prefix suggesting NVIDIA exclusivity, this extension has been adopted as a pseudo-standard and is supported by AMD and Intel drivers on Windows.6 This extension allows an OpenGL context to open a handle to a Direct3D device and "register" Direct3D resources. Once registered, a Direct3D texture appears to the OpenGL context as a standard Renderbuffer or Texture object. This allows the OpenGL engine to render directly into the Direct3D resource.8

#### **2.2.2 DXGI: The Underlying Fabric**

Underpinning modern Windows graphics is the DirectX Graphics Infrastructure (DXGI). DXGI manages low-level tasks independent of the Direct3D graphics runtime, such as enumerating adapters and managing swap chains. Crucially for this report, DXGI provides the mechanism for "Shared Handles." A resource created with the D3D11\_RESOURCE\_MISC\_SHARED flag can be assigned a global HANDLE by the operating system. This handle functions essentially as a pointer to the VRAM allocation that can be passed between processes and APIs.10 This DXGI layer is what makes the WGL\_NV\_DX\_interop bridge mechanically possible.

### **2.3 The "Air Gap" in agus-maps-flutter**

The current agus-maps-flutter implementation on Windows is described as "experimental" and a "Proof of Concept" in the provided research materials.1 While the Linux implementation leverages native GL texture sharing (likely via DMA-BUF or EGLImage), the Windows side faces the aforementioned API mismatch. The "tweak" is not merely a configuration change but a distinct architectural implementation. It requires the C++ plugin code to stop treating the Windows build as a generic desktop target and instead treat it as a specialized Direct3D-interop target. This involves writing Windows-specific C++ code that explicitly manages D3D11 devices, textures, and synchronization primitives, rather than relying on cross-platform OpenGL abstractions that fail to breach the D3D barrier.

## **3\. Technical Strategy: The Zero-Copy Implementation**

The proposed solution involves a four-phase implementation strategy. This strategy is derived from analyzing successful implementations in similar projects like media\_kit 11 and synthesizing technical documentation from Microsoft and NVIDIA regarding interop extensions.

### **3.1 Phase 1: Direct3D 11 Resource Management**

The foundation of the zero-copy pipeline is the Direct3D 11 texture. Unlike a standard OpenGL implementation where the texture is generated via glGenTextures, in this hybrid model, the texture must originate from Direct3D. This is because the Flutter Windows embedder expects a Direct3D resource (or a handle to one) to composite into its scene graph.13

The C++ plugin must initialize a ID3D11Device and ID3D11DeviceContext. It is critical that this device is created on the *same physical GPU adapter* as the one used by Flutter. On systems with hybrid graphics (e.g., Intel iGPU \+ NVIDIA dGPU), creating the texture on the wrong adapter will force the OS to copy the data across the system bus, reintroducing the latency we aim to eliminate.15

**Texture Specification for Zero-Copy:**

The texture creation descriptor (D3D11\_TEXTURE2D\_DESC) must be configured with precise flags to enable sharing and disable CPU access:

* **BindFlags**: Must include D3D11\_BIND\_RENDER\_TARGET (so OpenGL can write to it) and D3D11\_BIND\_SHADER\_RESOURCE (so Flutter can read from it).  
* **MiscFlags**: Must strictly include D3D11\_RESOURCE\_MISC\_SHARED or D3D11\_RESOURCE\_MISC\_SHARED\_KEYEDMUTEX.17 This signals the driver to allocate memory in a way that allows cross-API access.  
* **CPUAccessFlags**: Must be set to 0\. This is the code-level enforcement of the "no CPU mediation" requirement. Any non-zero value here implies CPU involvement, which is a performance regression.18  
* **Format**: Typically DXGI\_FORMAT\_B8G8R8A8\_UNORM. Flutter on Windows generally prefers BGRA formats. A mismatch here would force an implicit conversion copy by the GPU, consuming unnecessary cycles.

### **3.2 Phase 2: The WGL Interop Bridge**

Once the D3D11 texture is created, the "magic" of WGL\_NV\_DX\_interop is applied. The plugin must retrieve the function pointers for wglDXOpenDeviceNV and wglDXRegisterObjectNV at runtime.7

**Step-by-Step Bridging:**

1. **Device Association:** The plugin calls wglDXOpenDeviceNV(d3d11Device). This tells the OpenGL driver to establish a communication channel with the specified Direct3D device.  
2. **Object Registration:** The plugin calls wglDXRegisterObjectNV. This function takes the ID3D11Texture2D pointer and returns a handle. Crucially, it links this D3D texture to a generated OpenGL texture name (GLuint).  
3. **FBO Attachment:** The CoMaps engine, which expects to render to an OpenGL Framebuffer Object (FBO), is configured to attach this specific GLuint as its color attachment.

From the perspective of the CoMaps engine, nothing has changed. It is issuing standard draw calls (e.g., glDrawArrays, glDrawElements) to an OpenGL texture. However, the driver intercepts these writes and directs the pixel data directly into the memory addresses owned by the Direct3D texture. This redirection is hardware-accelerated and transparent, achieving the zero-copy goal.

### **3.3 Phase 3: Flutter Texture Registration via TextureVariant**

With the map rendered into the shared D3D texture, the final step is handing it off to Flutter for display. The Flutter Windows embedder provides a specific API for this: TextureRegistrar.

Traditional implementations might use PixelBufferTexture, which expects a pointer to system RAM. To achieve our goal, we must use GpuSurfaceTexture (wrapped in a TextureVariant). The registration structure FlutterDesktopGpuSurfaceDescriptor is the key interface.13

* **type**: This must be set to kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle.14 This enum explicitly tells the Flutter engine, "I am giving you a Windows resource handle, not a pointer to memory."  
* **handle**: This field is populated with the HANDLE obtained from the D3D11 texture via IDXGIResource::GetSharedHandle.10

By registering this handle, we essentially give Flutter a key to the locker where the map frame is stored. Flutter then wraps this handle in its own Skia surface and composites it into the application window. The data never passes through the CPU.

### **3.4 Phase 4: Synchronization and Keyed Mutexes**

The most critical and often overlooked aspect of this "tweak" is synchronization. Without it, the "Zero-Copy" pipeline becomes a "Race Condition" pipeline.

If Flutter tries to read the texture while CoMaps is still writing to it, the user will see screen tearing, flickering, or incomplete frames. Because the CPU is not mediating (copying takes time, which implicitly synchronizes), the GPU processes run asynchronously and largely independently.

To solve this, the IDXGIKeyedMutex interface is required.17

* **Mechanism:** The texture is created with the KeyedMutex flag. This creates a lock associated with the resource.  
* **Producer (CoMaps):** Before rendering, the OpenGL thread calls AcquireSync(1). This blocks the GPU (not the CPU) until the resource is free. After rendering, it calls ReleaseSync(0).  
* **Consumer (Flutter):** The Flutter engine (or the plugin's D3D side) calls AcquireSync(0) to read the texture. It waits for the key to be 0 (released by producer).

This "Ping-Pong" locking mechanism ensures perfect frame pacing without CPU stalls. Snippet 17 highlights that failing to manage these flags correctly can result in blank images or deadlocks, emphasizing the precision required in this implementation.

## **4\. Case Study and Comparative Analysis: media\_kit**

A significant portion of the research material references media\_kit as a precedent for high-performance rendering on Windows.11 Analyzing this library provides concrete validation for the proposed strategy.

### **4.1 Lessons form media\_kit**

media\_kit uses libmpv for video playback. Like CoMaps, libmpv renders via OpenGL. To display 4K 60fps video on Windows, media\_kit cannot afford a CPU copy.

* **Implementation Verification:** The research snippets reveal that media\_kit employs a class named ANGLESurfaceManager and utilizes VideoOutputManager to handle texture registration.12  
* **Shared Handles:** The documentation explicitly mentions usage of kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle and the necessity of managing EGLSurface and D3D11Device interactions.  
* **Validation:** The fact that media\_kit successfully renders high-bitrate video using this architecture confirms that agus-maps-flutter can achieve similar results for map rendering. The data bandwidth requirements for 4K video are often higher than vector map rendering, suggesting this solution provides ample headroom.

### **4.2 Divergence: Map vs. Video**

While the transport mechanism is identical, the rendering triggers differ. Video is time-based (a new frame every 16ms). Map rendering is event-based (render only when the user pans/zooms). The "tweak" for agus-maps-flutter must therefore include an intelligent Ticker or event loop integration. We cannot simply pump frames endlessly. The implementation must trigger the Acquire/Render/Release cycle only upon input events to maintain the battery efficiency touted by the repository.1

## **5\. Performance Implications and Benefits**

Implementing this zero-copy architecture yields measurable performance benefits that directly address the user's requirement for efficiency.

### **5.1 Bandwidth Savings**

In a Pixel Buffer approach, a 1920x1080 render target requires transferring approximately 8MB of data per frame. At 60 FPS, this equates to roughly 500 MB/s of continuous memory bandwidth. While modern buses can handle this, it creates contention with other system processes. The Zero-Copy approach reduces this transfer to **0 MB/s**, as the data remains static in VRAM. The only bandwidth used is for the lightweight commands and synchronization tokens.

### **5.2 Latency Reduction**

The "Air Gap" copy typically introduces at least one frame of latency (16ms at 60Hz) as the CPU must wait for the GPU to finish rendering before it can read the pixels (a pipeline stall). Zero-copy allows the consumer to read the texture immediately after the fence is signaled, potentially reducing input-to-photon latency significantly. This makes the map feel "stickier" and more responsive to touch gestures.

### **5.3 Power Consumption**

By removing the heavy memcpy operations from the CPU, the processor can enter lower power states more frequently. This is critical for laptop users running the application on battery. The CPU usage profile shifts from a constant load (data shuffling) to a purely event-driven profile (command dispatch).

## **6\. Detailed Implementation Blueprint**

To execute this "tweak," the following concrete steps must be taken within the agus-maps-flutter Windows plugin code (C++).

### **6.1 Dependency Configuration**

The CMakeLists.txt for the windows plugin must be updated to link against d3d11.lib, dxgi.lib, and potentially opengl32.lib. The WGL extensions usually require a helper header like wglext.h.

### **6.2 The Rendering Class Structure**

A new class, likely D3D11TextureBridge, should be introduced to encapsulate the complexity.

**Key Member Variables:**

* ID3D11Device\* d3d\_device\_: The interop device.  
* ID3D11Texture2D\* shared\_texture\_: The actual storage resource.  
* HANDLE shared\_handle\_: The DXGI token passed to Flutter.  
* HANDLE gl\_interop\_device\_: The WGL handle returned by wglDXOpenDeviceNV.  
* HANDLE gl\_interop\_object\_: The handle returned by wglDXRegisterObjectNV.  
* GLuint gl\_texture\_id\_: The OpenGL name used by CoMaps.

### **6.3 Critical Code Logic (Pseudocode Analysis)**

**Initialization:**

C++

// 1\. Initialize D3D11 Device (Preferably on same adapter as Flutter)  
D3D11CreateDevice(..., \&d3d\_device\_,...);

// 2\. Configure Texture Description  
D3D11\_TEXTURE2D\_DESC desc \= {};  
desc.Width \= width;  
desc.Height \= height;  
desc.Format \= DXGI\_FORMAT\_B8G8R8A8\_UNORM; // Match Flutter  
desc.Usage \= D3D11\_USAGE\_DEFAULT;  
desc.BindFlags \= D3D11\_BIND\_RENDER\_TARGET | D3D11\_BIND\_SHADER\_RESOURCE;  
desc.MiscFlags \= D3D11\_RESOURCE\_MISC\_SHARED\_KEYEDMUTEX; // Enable Sync

// 3\. Create Texture  
d3d\_device\_-\>CreateTexture2D(\&desc, nullptr, \&shared\_texture\_);

// 4\. Get Shared Handle  
IDXGIResource\* dxgi\_res;  
shared\_texture\_-\>QueryInterface(\_\_uuidof(IDXGIResource), \&dxgi\_res);  
dxgi\_res-\>GetSharedHandle(\&shared\_handle\_);

// 5\. Register with WGL (OpenGL)  
gl\_interop\_device\_ \= wglDXOpenDeviceNV(d3d\_device\_);  
gl\_interop\_object\_ \= wglDXRegisterObjectNV(gl\_interop\_device\_, shared\_texture\_, gl\_texture\_id\_, GL\_TEXTURE\_2D, WGL\_ACCESS\_READ\_WRITE\_NV);

**The Render Loop:**

C++

// 1\. Lock for GL Access  
wglDXLockObjectsNV(gl\_interop\_device\_, 1, \&gl\_interop\_object\_);

// 2\. Render Map  
map\_engine\_-\>Render(gl\_texture\_id\_); // Render to the specific texture

// 3\. Unlock and Flush  
wglDXUnlockObjectsNV(gl\_interop\_device\_, 1, \&gl\_interop\_object\_);

// 4\. Notify Flutter  
texture\_registrar\_-\>MarkTextureFrameAvailable(flutter\_texture\_id\_);

**Flutter Registration:**

C++

FlutterDesktopGpuSurfaceDescriptor variant\_desc \= {};  
variant\_desc.handle \= shared\_handle\_; // Pass the handle, NOT the pixels  
variant\_desc.type \= kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;  
//... Set width/height...

This logic directly satisfies the user's request: Efficient (hardware accelerated), Zero-Copy (shared handle), and No CPU Mediation (direct driver-level access).

## **6.5 Repository-Specific Fixes (Implemented)**

The following fixes were required in the current repo to make the theoretical pipeline above work reliably on Windows:

1. **GL context must be current during interop registration.** WGL interop registration can fail with `GL_INVALID_OPERATION` if the OpenGL context is not current on the calling thread. The interop registration now explicitly makes the GL context current for the `wglDXRegisterObjectNV` sequence.

2. **GL_CLAMP_TO_EDGE must be defined on Windows builds.** Some Windows OpenGL headers do not expose `GL_CLAMP_TO_EDGE`, which caused compilation failures. The constant is now defined when missing.

3. **Interop FBO completeness required extra setup.** The interop-backed FBO initially reported `GL_FRAMEBUFFER_UNSUPPORTED`. Fixes required:
	- A **renderbuffer fallback** path to isolate texture compatibility issues.
	- Explicit `glDrawBuffers` and `glReadBuffer` setup on the interop FBO.
	- Locking the interop object **before** FBO attachment and status checks, then unlocking afterward.

4. **CPU fallback required RGBA→BGRA swizzle.** The Flutter texture expects BGRA; the CPU copy path now converts from OpenGL RGBA to BGRA to avoid inverted colors.

5. **Adapter matching is mandatory on multi-GPU systems.** The D3D11 device is forced to match the adapter used by Flutter (via DXGI LUID matching against the active OpenGL renderer). This prevents implicit cross-GPU copies and interop failures.

6. **Overlay orientation differs by path.** The zero-copy path uses a top-left origin (to match the shared-handle texture orientation after the Y flip in the copy), while the CPU path uses bottom-left. The overlay rendering now selects the correct origin per path to avoid mirrored/bottom-right text.

## **7\. Future Considerations and Risks**

### **7.1 The Vulkan Horizon**

The research material alludes to the rise of Vulkan and its superiority in multi-threading and explicit control.21 While CoMaps supports Vulkan, the current Flutter Windows Embedder heavily favors the D3D11/ANGLE path. However, looking forward, migrating to Vulkan could offer even more granular control over synchronization. For now, OpenGL-D3D interop is the stable, production-ready path. A Vulkan rewrite would require a significantly larger overhaul of both the plugin and potentially the Flutter engine's shell interaction on Windows.

### **7.2 Driver Stability**

Dependency on WGL\_NV\_DX\_interop introduces a reliance on GPU driver quality. While major vendors support it, edge cases with outdated drivers or specific integrated graphics chipsets can cause instability. A robust implementation should include a "safe mode" fallback to the Pixel Buffer method if the interop initialization fails. This ensures that while performance might degrade on unsupported hardware, the application remains functional.

### **7.3 Multi-GPU Systems**

As highlighted in the media\_kit analysis, systems with multiple GPUs pose a risk. If Flutter initializes on the discrete GPU and the plugin initializes on the integrated GPU, the shared\_handle might function but effectively trigger a memory copy over the PCI bus to move the data between cards.16 The "tweak" must strictly enforce adapter matching by querying the LUID of the active Flutter device and forcing the plugin's D3D device to match it.

## **8\. Conclusion**

The analysis conclusively validates that an efficient, zero-copy memory pipeline with no CPU mediation can be engineered for the agus-maps-flutter repository on Windows. The solution does not require a rewrite of the core CoMaps engine but rather a targeted architectural "tweak" to the Windows-specific hosting code.

By abandoning the generic, CPU-bound pixel buffer approach and embracing the **WGL\_NV\_DX\_interop** extension and **DXGI Shared Handles**, developers can bridge the OpenGL-DirectX divide. This approach leverages the specialized hardware capabilities of the Windows platform to deliver a rendering experience that is fluid, responsive, and resource-efficient. The precedent set by media\_kit serves as a strong proof of concept, and the technical path outlined in this report provides the blueprint for execution.

Implementing this optimization transforms the map rendering from a "functional port" to a "native-class experience," fulfilling the rigorous performance requirements of modern desktop applications.

| Feature | Legacy Implementation | Optimized "Tweaked" Implementation |
| :---- | :---- | :---- |
| **Transport Medium** | System RAM (CPU) | VRAM (GPU) |
| **Data Copy** | glReadPixels (Slow) | WGL\_NV\_DX Alias (Instant) |
| **Synchronization** | Implicit (Blocking) | Keyed Mutex (Async) |
| **CPU Usage** | High (Memcpy overhead) | Low (Control logic only) |
| **Latency** | High (1-2 Frames) | Low (\<1 Frame) |
| **Scalability** | Limited by Bus Speed | Limited by GPU Core |

The path forward is clear: integrate the interop bridge, secure the synchronization, and unlock the full potential of the GPU for mapping on Windows.

#### **Works cited**

1. agus-works/agus-maps-flutter: Offline-first Flutter map widget powered by CoMaps/Organic Maps. Native C++ rendering via FFI with GPU texture sharing—no PlatformView overhead. Supports Android, iOS, macOS, Windows & Linux. \- GitHub, accessed January 17, 2026, [https://github.com/agus-works/agus-maps-flutter](https://github.com/agus-works/agus-maps-flutter)  
2. MAPLIBRE-RS: TOWARD PORTABLE MAP RENDERERS \- Semantic Scholar, accessed January 17, 2026, [https://pdfs.semanticscholar.org/f97d/584d493f85d82dba8cff1e911d61f00519ca.pdf](https://pdfs.semanticscholar.org/f97d/584d493f85d82dba8cff1e911d61f00519ca.pdf)  
3. OpenGL external textures for Windows · Issue \#162273 · flutter/flutter \- GitHub, accessed January 17, 2026, [https://github.com/flutter/flutter/issues/162273](https://github.com/flutter/flutter/issues/162273)  
4. Flutter integration with OpenGL like apploica : r/flutterhelp \- Reddit, accessed January 17, 2026, [https://www.reddit.com/r/flutterhelp/comments/1ibhhro/flutter\_integration\_with\_opengl\_like\_apploica/](https://www.reddit.com/r/flutterhelp/comments/1ibhhro/flutter_integration_with_opengl_like_apploica/)  
5. Flutter Analysis and Practice: Same Layer External Texture Rendering \- Alibaba Cloud, accessed January 17, 2026, [https://www.alibabacloud.com/blog/flutter-analysis-and-practice-same-layer-external-texture-rendering\_596580](https://www.alibabacloud.com/blog/flutter-analysis-and-practice-same-layer-external-texture-rendering_596580)  
6. Initial checkin of WGL\_NV\_DX demo \- GitHub, accessed January 17, 2026, [https://github.com/halogenica/WGL\_NV\_DX](https://github.com/halogenica/WGL_NV_DX)  
7. WGL\_NV\_DX\_interop \- CCR's Blog \-, accessed January 17, 2026, [https://dejaloser.github.io/2016/09/06/wgl\_nv\_dx\_interop.html](https://dejaloser.github.io/2016/09/06/wgl_nv_dx_interop.html)  
8. Sharing a texture between direct3d and opengl? \- Stack Overflow, accessed January 17, 2026, [https://stackoverflow.com/questions/1601165/sharing-a-texture-between-direct3d-and-opengl](https://stackoverflow.com/questions/1601165/sharing-a-texture-between-direct3d-and-opengl)  
9. WGL\_NV\_DX\_interop \- OpenGL: Advanced Coding \- Khronos Forums, accessed January 17, 2026, [https://community.khronos.org/t/wgl-nv-dx-interop/63240](https://community.khronos.org/t/wgl-nv-dx-interop/63240)  
10. ID3D11Device::OpenSharedResource (d3d11.h) \- Win32 apps | Microsoft Learn, accessed January 17, 2026, [https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11device-opensharedresource](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11device-opensharedresource)  
11. noelex/media\_kit: A complete video & audio library for Flutter & Dart. \- GitHub, accessed January 17, 2026, [https://github.com/noelex/media\_kit](https://github.com/noelex/media_kit)  
12. drwankingstein/media\_kit: \[WIP\] A complete video & audio library for Flutter & Dart. \- GitHub, accessed January 17, 2026, [https://github.com/drwankingstein/media\_kit](https://github.com/drwankingstein/media_kit)  
13. Flutter Windows Embedder: shell/platform/common/public/flutter\_texture\_registrar.h Source File, accessed January 17, 2026, [https://api.flutter.dev/windows-embedder/flutter\_\_texture\_\_registrar\_8h\_source.html](https://api.flutter.dev/windows-embedder/flutter__texture__registrar_8h_source.html)  
14. Flutter Windows Embedder: shell/platform/common/public/flutter\_texture\_registrar.h File Reference, accessed January 17, 2026, [https://api.flutter.dev/windows-embedder/flutter\_\_texture\_\_registrar\_8h.html](https://api.flutter.dev/windows-embedder/flutter__texture__registrar_8h.html)  
15. CopyResource from one D3D11 device to another \- Stack Overflow, accessed January 17, 2026, [https://stackoverflow.com/questions/28456783/copyresource-from-one-d3d11-device-to-another](https://stackoverflow.com/questions/28456783/copyresource-from-one-d3d11-device-to-another)  
16. Share a D3D 11 texture across GPUs \- Stack Overflow, accessed January 17, 2026, [https://stackoverflow.com/questions/54756881/share-a-d3d-11-texture-across-gpus](https://stackoverflow.com/questions/54756881/share-a-d3d-11-texture-across-gpus)  
17. D3DX11SaveTextureToFile with shared resources \- Game Development Stack Exchange, accessed January 17, 2026, [https://gamedev.stackexchange.com/questions/10725/d3dx11savetexturetofile-with-shared-resources](https://gamedev.stackexchange.com/questions/10725/d3dx11savetexturetofile-with-shared-resources)  
18. D3D11 screen desktop copy to ID3D11Texture2D \- Stack Overflow, accessed January 17, 2026, [https://stackoverflow.com/questions/29661380/d3d11-screen-desktop-copy-to-id3d11texture2d](https://stackoverflow.com/questions/29661380/d3d11-screen-desktop-copy-to-id3d11texture2d)  
19. Flutter Windows Embedder: flutter::TextureRegistrar Class Reference, accessed January 17, 2026, [https://api.flutter.dev/windows-embedder/classflutter\_1\_1\_texture\_registrar.html](https://api.flutter.dev/windows-embedder/classflutter_1_1_texture_registrar.html)  
20. Using Unity Texture in native Direct3D 11 DLL \- DEVICE\_OPEN\_SHARED\_RESOURCE\_INVALIDARG\_RETURN \- Stack Overflow, accessed January 17, 2026, [https://stackoverflow.com/questions/75300948/using-unity-texture-in-native-direct3d-11-dll-device-open-shared-resource-inva](https://stackoverflow.com/questions/75300948/using-unity-texture-in-native-direct3d-11-dll-device-open-shared-resource-inva)  
21. How I learned Vulkan and wrote a small game engine with it (2024) \- Hacker News, accessed January 17, 2026, [https://news.ycombinator.com/item?id=46010329](https://news.ycombinator.com/item?id=46010329)  
22. Why Vulkan Is Better (But You Might Want OpenGL Anyway) | by Kshitijaucharmal \- Medium, accessed January 17, 2026, [https://medium.com/fossible/why-vulkan-is-better-but-you-might-want-opengl-anyway-f797cf9cfaea](https://medium.com/fossible/why-vulkan-is-better-but-you-might-want-opengl-anyway-f797cf9cfaea)
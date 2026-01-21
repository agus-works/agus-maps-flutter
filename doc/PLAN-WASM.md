# WASM/Web Support Analysis for Agus Maps Flutter

## Executive Summary

This document provides a comprehensive analysis of implementing WebAssembly (WASM) support for the Agus Maps Flutter plugin. The goal is to enable full-featured offline map rendering in web browsers through WASM, prioritizing **complete offline execution with bundled MWM maps** over maximum performance optimization.

The analysis covers:
1. **Current Architecture Review** - How rendering works on all supported platforms
2. **Asset Management Strategy** - How maps and data files would be handled on web
3. **WASM Compilation & Execution** - Technical approach to compiling CoMaps for WASM
4. **Browser Storage & Offline Persistence** - Strategies for storing large MWM files locally
5. **Rendering Pipeline** - Adapting zero-copy GPU patterns for web Canvas/WebGL
6. **Recommended Implementation Path** - Realistic, phased approach
7. **Risk Assessment & Trade-offs** - Known challenges and limitations


## Table of Contents

1. [Current Architecture Analysis](#current-architecture-analysis)
2. [Asset Management Strategy](#asset-management-strategy)
3. [WASM Compilation Strategy](#wasm-compilation-strategy)
4. [Browser Storage Solutions](#browser-storage-solutions)
5. [Rendering Architecture for Web](#rendering-architecture-for-web)
6. [API Surface & Dart-WASM Bridge](#api-surface--dart-wasm-bridge)
7. [Implementation Phases](#implementation-phases)
8. [Risk Assessment](#risk-assessment)
9. [Success Criteria](#success-criteria)


## Current Architecture Analysis

### Platform Comparison Matrix

```
┌─────────────┬──────────────────┬───────────────┬──────────────────┬────────────────┐
│ Platform    │ Graphics API     │ Texture Share │ Frame Transfer   │ Thread Model   │
├─────────────┼──────────────────┼───────────────┼──────────────────┼────────────────┤
│ iOS/macOS   │ Metal            │ CVPixelBuffer │ Zero-copy GPU    │ GCD dispatch   │
│             │                  │ + IOSurface   │ shared memory    │ to main thread │
├─────────────┼──────────────────┼───────────────┼──────────────────┼────────────────┤
│ Android     │ OpenGL ES 3.0    │ SurfaceTexture│ Zero-copy EGL    │ JNI to UI      │
│             │                  │               │ window surface   │ thread         │
├─────────────┼──────────────────┼───────────────┼──────────────────┼────────────────┤
│ Windows     │ OpenGL + D3D11   │ DXGI Shared   │ CPU-mediated     │ PostMessage    │
│             │                  │ Handle        │ glReadPixels+copy│ WM_USER        │
├─────────────┼──────────────────┼───────────────┼──────────────────┼────────────────┤
│ Linux       │ EGL + OpenGL ES  │ FlPixelBuffer │ CPU-mediated     │ GLib event     │
│             │ 3.0              │ Texture       │ glReadPixels+copy│ loop           │
├─────────────┼──────────────────┼───────────────┼──────────────────┼────────────────┤
│ Web (WASM)  │ WebGL 2.0        │ Canvas        │ CPU-mediated     │ JS event loop  │
│             │                  │ ImageData     │ readPixels+memcpy│ + Workers      │
└─────────────┴──────────────────┴───────────────┴──────────────────┴────────────────┘
```

### Rendering Pipeline Principles (Currently Implemented)

All platforms follow these high-level patterns:

1. **Initialization Phase:**
   - Extract/locate resource files (classificator.txt, types.txt, etc.)
   - Extract/locate MWM map files
   - Create Framework with resource/writable paths
   - Initialize DrapeEngine with surface dimensions
   - Create graphics context (Metal/OpenGL/D3D11)

2. **Frame Rendering Loop:**
   - User input (touch/mouse/scroll) → RenderFrame() in FrontendRenderer thread
   - Scene update (tiles, overlays, routes)
   - Graphics context rendering to GPU surface
   - Frame notification back to UI thread
   - UI thread signals texture available to Flutter

3. **Memory Access Pattern:**
   - MWM files memory-mapped via `mmap()` on desktop/mobile
   - Only visible tile data paged into RAM
   - ~10-50MB RAM per visible region (not the full file size)

4. **Platform-Specific Optimizations:**
   - **iOS/macOS:** Zero-copy via IOSurface (GPU shared memory)
   - **Android:** Zero-copy via SurfaceTexture (EGL native window)
   - **Windows/Linux:** CPU-mediated (`glReadPixels` → staging buffer)

### Key Insight: CPU-Mediated Model Works for Web

Windows and Linux implementations already use CPU-mediated pixel transfer (glReadPixels → buffer copy). This is **directly analogous to WebGL readPixels + Canvas updates**, suggesting the web implementation would follow a similar pattern with acceptable overhead.


## Asset Management Strategy

### Current Asset Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ Bundled/Downloaded Assets Distribution                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ 1. SOURCE ASSETS (committed to thirdparty/comaps)                   │
│    • CoMaps data files (100+ JSON localization files)               │
│    • Engine data: classificator.txt, types.txt, categories.txt      │
│    • Fonts, symbols, style definitions                              │
│    • ICU data: icudt75l.dat (~1.3 MB)                               │
│    • MWM maps: World, WorldCoasts, regional maps                    │
│                                                                     │
│ 2. PLATFORM DISTRIBUTION                                            │
│    • Flutter assets/ directory                                      │
│    • Platform-specific asset packaging (APK/IPA/exe)                │
│    • App installation includes all bundled assets                   │
│                                                                     │
│ 3. RUNTIME EXTRACTION                                               │
│    • Platform channel (extractMap, extractDataFiles)                │
│    • Extract to writable filesystem path                            │
│    • Framework loads from writable path                             │
│    • MwmStorage tracks metadata (version, size, hash)               │
│                                                                     │
│ 4. OPTIONAL: DYNAMIC MAP DOWNLOADS                                  │
│    • MirrorService fetches additional maps on-demand                │
│    • Downloads to writable directory                                │
│    • RegisterSingleMap() registers dynamically                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Web Asset Distribution Strategy

#### Option A: Bundled Assets (Recommended for MVP)

**Concept:** Include all essential assets in the WASM bundle/HTTP response, cached in IndexedDB.

```
Web App Bundle (~200-500 MB compressed):
├── app.js                          (Flutter web app)
├── comaps_engine.wasm              (4-8 MB wasm binary)
├── comaps_data.tar.gz/bundle       (Engine data files, ~50 MB)
│   ├── classificator.txt
│   ├── types.txt
│   ├── categories.txt
│   ├── fonts/
│   ├── styles/
│   └── symbols/
├── maps/
│   ├── World.mwm                   (50 MB)
│   ├── WorldCoasts.mwm             (8 MB)
│   └── Gibraltar.mwm               (5 MB)
└── icu/
    └── icudt75l.dat                (1.3 MB)

Initial page load:
1. HTML loads with service worker
2. Service worker intercepts fetch for wasm, data, maps
3. IndexedDB checked for cached assets
4. If missing or outdated, download and cache
5. App uses cached files via virtual filesystem (Emscripten)
```

**Pros:**
- True offline capability after first load
- No additional network calls once cached
- Consistent with native plugin philosophy
- Service worker handles caching automatically

**Cons:**
- Large initial download (~100-200 MB depending on maps)
- Browser disk quota limits (typically 50 MB - 1 GB depending on browser)
- Need clear update strategy for asset changes

**Best For:** Desktop browsers, users with stable internet, regional maps (not all global maps)

#### Option B: Dynamic Asset Loading (Progressive)

**Concept:** Start with minimal assets, load additional maps on-demand.

```
Minimal Bundle (~100 MB):
├── app.js
├── comaps_engine.wasm
├── comaps_data.tar.gz              (essential engine files only)
└── World.mwm + WorldCoasts.mwm     (base maps)

Dynamic Downloads (user-initiated):
• User selects a region → checks IndexedDB
• If not cached, fetch from S3/CDN
• Download to IndexedDB or temporary storage
• Register with engine via registerSingleMap()
```

**Pros:**
- Smaller initial download
- Flexible storage management
- Can support unlimited regions (if user downloads selectively)

**Cons:**
- Network dependency for new regions
- Requires download UI/state management
- Inconsistent with "fully offline" goal (but good fallback)

**Best For:** Web apps where not all maps needed, mobile browsers with quota concerns

#### Option C: Virtual Filesystem with Network Access (Hybrid)

**Concept:** WASM accesses a virtual filesystem that can be partly in-memory, partly cached, partly from network.

```
Emscripten Virtual FS Layers:
├── Memory FS (maps loaded to RAM)
│   └── /data/ (small cache of frequently-accessed files)
├── IndexedDB FS (persistent browser storage)
│   └── /maps/ (full MWM files)
└── Network FS (optional on-demand, with fallback)
    └── /remote/ (downloads on-demand if not cached)
```

**Pros:**
- Flexible, composable approach
- Can optimize each asset type (engine data → memory, maps → IndexedDB)
- Graceful degradation (works offline if cached, works online if not)

**Cons:**
- Complex to implement correctly
- Harder to reason about storage state
- More moving parts to test

**Best For:** Production apps with sophisticated storage management

### Recommended Strategy: Hybrid Bundling

**For MVP (web.1):**
1. Bundle all essential engine data files in WASM app
2. Bundle 1-2 representative maps (World + one regional, e.g., Gibraltar)
3. Use IndexedDB for persistent cache of bundled assets
4. Support dynamic map registration for user-downloaded maps
5. MwmStorage Dart class adapted to track browser-based maps

**For web.2:**
- Implement progressive download UI for additional regions
- Support S3/CDN mirror service for map downloads
- Add storage quota awareness and cleanup prompts


## WASM Compilation Strategy

### Emscripten as the Bridge

The recommended approach uses **Emscripten** to compile CoMaps C++ code to WebAssembly.

```
Compilation Pipeline:
┌──────────────────────────────────────────────────────────────┐
│ CoMaps C++ Source (libs/, 3party/)                           │
├──────────────────────────────────────────────────────────────┤
│                          ↓                                   │
│              Emscripten CMake Toolchain                      │
│              (cmake -DCMAKE_TOOLCHAIN_FILE=...)              │
├──────────────────────────────────────────────────────────────┤
│         C++ → LLVM IR → WebAssembly Binary                   │
├──────────────────────────────────────────────────────────────┤
│              comaps_engine.wasm (~4-8 MB)                    │
│              comaps_engine.js   (glue code)                  │
│              comaps_engine.wasm.map (sourcemap)              │
└──────────────────────────────────────────────────────────────┘
```

### Critical Compilation Considerations

#### 1. **Threading Model Mismatch**

**Challenge:** CoMaps uses `pthread` for FrontendRenderer and BackendRenderer threads. WASM/JavaScript is single-threaded (in the main thread).

**Solutions:**

a) **Web Workers (Recommended):**
```cpp
// In Emscripten + pthreads mode
#if __EMSCRIPTEN_PTHREADS__
  // pthread becomes Web Worker under the hood
  pthread_t renderer_thread;
  pthread_create(&renderer_thread, nullptr, FrontendRendererThread, nullptr);
  // Emscripten automatically marshals this to a Web Worker
#endif
```
- Emscripten can compile `pthread` code to Web Workers
- Requires `PTHREAD_POOL_SIZE` configuration (~2 workers sufficient)
- Shared memory constraints due to SharedArrayBuffer security model

b) **Refactor to Single-Thread Mode:**
- Move rendering to requestAnimationFrame loop (main JS thread)
- Use MessagePorts for IPC instead of pthread mutexes
- More complex refactoring, but avoids SharedArrayBuffer

**Recommendation:** Start with **Emscripten pthreads mode** (option a), as it requires fewer code changes.

#### 2. **Graphics Context Factory**

**Challenge:** Metal, OpenGL, D3D11, EGL context creation depends on native window handles.

**For WASM, WebGL is the target:**

```cpp
// New: AgusWebGlContextFactory.cpp
class AgusWebGlContextFactory : public dp::GraphicsContextFactory {
public:
  void PrepareContext() override {
    // WebGL context is already created by browser
    // Emscripten exposes it as gl_ctx (via emscripten_webgl_get_current_context)
  }
  
  void MakeCurrent(dp::GraphicsContext* context) override {
    // WASM/WebGL contexts are implicitly current
    // No state management needed (unlike OpenGL threading)
  }
  
  void DoneCurrent() override {
    // No-op for WebGL
  }
};
```

This would be a new platform-specific file: `src/AgusWebGlContextFactory.cpp`

#### 3. **File I/O and Virtual Filesystem**

**Challenge:** WASM has no direct filesystem access. All I/O must go through Emscripten's virtual FS.

**Approach:**

```cpp
// Emscripten automatically maps file operations
// Just use std::ifstream as normal - it works transparently
#include <iostream>
#include <fstream>

void LoadMap(const char* path) {
  // This transparently uses Emscripten's MEMFS/IDBFS
  std::ifstream file(path, std::ios::binary);
  // ... read file ...
}
```

**Filesystem Mount Points:**

```javascript
// JavaScript initialization
FS.createPath('/', 'comaps', true, true);
FS.createPath('/comaps', 'maps', true, true);

// Mount IndexedDB (for persistent storage)
FS.mount(IDBFS, {autoPersist: true}, '/comaps/maps');

// Or manually mount bundled tar.gz
// (Emscripten can decompress inline)
```

#### 4. **Platform Detection and Conditional Compilation**

The codebase already has platform detection:

```cpp
#if __ANDROID__
  // Android-specific code
#elif __APPLE__
  // iOS/macOS
#elif _WIN32
  // Windows
#elif __linux__ && !__ANDROID__
  // Linux
#endif
```

**New:** Add WASM detection:

```cpp
#if __EMSCRIPTEN__
  // WASM-specific code
  // Use WebGL context factory
  // Use Emscripten file I/O
#endif
```

### CMake Configuration for Emscripten

```cmake
# CMakeLists.txt additions
if(EMSCRIPTEN)
  # Use Emscripten toolchain (automatically set by -DCMAKE_TOOLCHAIN_FILE)
  
  # Threading support via pthreads → Web Workers
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread")
  
  # Enable exception handling (adds ~40 KB to binary)
  # set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fexceptions")
  
  # Size optimization
  set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -flto")
  
  # Link to WebGL
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s USE_WEBGL2=1")
  
  # Thread pool for pthread emulation
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s PTHREAD_POOL_SIZE=2")
  
  # Allow fetch from CDN/S3
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s ALLOW_MEMORY_GROWTH=1")
endif()
```

### Patch Requirements for WASM

Several existing patches would need minor adjustments or new patches created:

1. **Resource Loading (0002-platform-directory-resources.patch):**
   - Add WASM path handling in Platform::GetReader()
   - Emscripten paths use `/` prefix with virtual FS mount points

2. **New Patch: WebGL Context Factory Selection**
   - Add `AgusWebGlContextFactory` selection when `__EMSCRIPTEN__`
   - Ensure proper initialization in `dp::CreateDrapeEngine`

3. **Possible: Reduce Optional Features**
   - Some patches related to Vulkan (Windows) can be skipped in WASM build
   - ICU/transliteration may remain, or be conditional

### Binary Size Expectations

```
WASM Binary Breakdown (estimated):
├── CoMaps Core           ~2.5 MB
├── Graphics/Rendering    ~1.2 MB
├── File/Resource Libs    ~0.8 MB
├── ICU Library           ~0.6 MB
├── Emscripten Runtime    ~0.4 MB
├── LTO/Optimization      ~(+50% overhead if not optimized)
│
Total (uncompressed):     ~5.5-6 MB
Total (gzipped):          ~2-2.5 MB
```

**Comparison:**
- iOS/macOS xcframework: ~30-50 MB (includes debug symbols, multiple architectures)
- Android .so: ~8-12 MB (per ABI)
- WASM is competitive and distributes more easily


## Browser Storage Solutions

### Browser Storage APIs Comparison

```
┌──────────────────┬────────────┬──────────────┬────────────┬──────────────┐
│ API              │ Per-Origin │ Persistence  │ Async      │ Size Limit   │
├──────────────────┼────────────┼──────────────┼────────────┼──────────────┤
│ LocalStorage     │ 5-10 MB    │ Permanent    │ Sync       │ Small files  │
│ SessionStorage   │ 5-10 MB    │ Tab lifetime │ Sync       │ Small files  │
│ IndexedDB        │ 50 MB - 2GB│ Permanent    │ Async      │ Large files  │
│ Cache API        │ Unlimited* │ Permanent    │ Async      │ With SW      │
│ FileSystem API   │ Unlimited* │ Permanent    │ Async      │ New standard │
└──────────────────┴────────────┴──────────────┴────────────┴──────────────┘
* Persistent storage permission required
```

### Recommended: IndexedDB for MWM Files

**Why IndexedDB:**
- Large storage capacity (100 MB - 2 GB depending on browser)
- Persistent across page reloads
- Efficient binary blob storage
- Can store metadata alongside files
- Good browser support (all modern browsers)

**Example Architecture:**

```javascript
// indexeddb.js
class MapStorage {
  constructor() {
    this.dbName = 'agus_maps_flutter_web';
    this.stores = ['maps', 'metadata', 'engine_data'];
  }
  
  async init() {
    const request = indexedDB.open(this.dbName, 1);
    
    request.onupgradeneeded = (e) => {
      const db = e.target.result;
      db.createObjectStore('maps', { keyPath: 'name' });
      db.createObjectStore('metadata', { keyPath: 'regionName' });
      db.createObjectStore('engine_data', { keyPath: 'filename' });
    };
    
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  
  async putMap(name, blobData, metadata) {
    // Store MWM file as Blob
    const store = this.db.transaction('maps', 'readwrite').objectStore('maps');
    store.put({name, data: blobData, timestamp: Date.now()});
    
    // Store metadata
    const metaStore = this.db.transaction('metadata', 'readwrite').objectStore('metadata');
    metaStore.put(metadata);
  }
  
  async getMap(name) {
    const store = this.db.transaction('maps', 'readonly').objectStore('maps');
    return new Promise((resolve, reject) => {
      const request = store.get(name);
      request.onsuccess = () => resolve(request.result?.data);
      request.onerror = () => reject(request.error);
    });
  }
  
  async getAllMetadata() {
    const store = this.db.transaction('metadata', 'readonly').objectStore('metadata');
    return new Promise((resolve) => {
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result);
    });
  }
}
```

### Virtual Filesystem Integration

**Emscripten's IDBFS (IndexedDB Filesystem):**

```javascript
// Initialize Emscripten FS with IndexedDB persistence
FS.createPath('/', 'comaps', true, true);
FS.mount(IDBFS, {autoPersist: true}, '/comaps/maps');

// Persist to IndexedDB (async)
FS.syncfs(false, (err) => {
  if (err) console.error('Failed to sync to IndexedDB:', err);
});

// Load from IndexedDB into memory (async)
FS.syncfs(true, (err) => {
  if (err) console.error('Failed to sync from IndexedDB:', err);
});
```

**Custom Integration:**

For finer control, bypass Emscripten's IDBFS and implement custom:

```cpp
// Dart→JS bridge calls JS storage API
// JS: await mapStorage.getMap('Gibraltar.mwm')
// Returns: ArrayBuffer
// C++: writes to Emscripten MEMFS via open()/write()

// Or: Mount files via Emscripten's LazyFile API
// Emscripten.FS.createLazyFile('/maps', 'Gibraltar.mwm', 
//   async () => { return await mapStorage.getMap('Gibraltar.mwm') }, 
//   true, false);
```

### Storage Quota Handling

```javascript
// Check available storage quota
const estimate = await navigator.storage.estimate();
const usage = estimate.usage;    // bytes used
const quota = estimate.quota;    // bytes available
const percent = (usage / quota) * 100;

// Request persistent storage permission
if (navigator.permissions?.query) {
  const permission = await navigator.permissions.query({name: 'persistent-storage'});
  if (permission.state === 'granted') {
    console.log('Has persistent storage permission');
  }
}

// Cleanup: remove old cached maps if over quota
async function enforceSizeLimit(maxBytes) {
  const metadata = await mapStorage.getAllMetadata();
  metadata.sort((a, b) => b.downloadDate - a.downloadDate); // newest first
  
  let total = 0;
  const toDelete = [];
  
  for (const m of metadata) {
    if (total > maxBytes) {
      toDelete.push(m.regionName);
    }
    total += m.fileSize;
  }
  
  for (const region of toDelete) {
    await mapStorage.deleteMap(region);
  }
}
```

### Service Worker for Caching

```javascript
// service-worker.js
const CACHE_NAME = 'agus-maps-flutter-v1';
const ASSETS_TO_CACHE = [
  '/index.html',
  '/app.js',
  '/comaps_engine.wasm',
  '/comaps_engine.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS_TO_CACHE);
    })
  );
});

self.addEventListener('fetch', (event) => {
  // For WASM and assets: use cache, fall back to network
  // For maps: try IndexedDB first, then network, then offline stub
  
  if (event.request.url.includes('.wasm') || 
      event.request.url.includes('app.js')) {
    event.respondWith(
      caches.match(event.request).then((response) => {
        return response || fetch(event.request);
      })
    );
  } else if (event.request.url.includes('/api/maps/')) {
    event.respondWith(
      mapStorage.getMap(mapName).then((blob) => {
        return new Response(blob);
      }).catch(() => fetch(event.request))
    );
  }
});
```


## Rendering Architecture for Web

### Graphics Pipeline Adaptation

The existing rendering loop can be largely reused with a WebGL backend:

```
┌────────────────────────────────────────────────────────────┐
│                    Current (Native)                        │
├────────────────────────────────────────────────────────────┤
│ FrontendRenderer Thread                                    │
│  • RenderFrame() every VSync or on demand                  │
│  • Updates scene (tiles, overlays)                         │
│  • OpenGL render calls to FBO/Texture                      │
│  • eglSwapBuffers() → signals frame ready                  │
│                                                            │
│ Main Thread Receives Frame-Ready Notification              │
│  • textureFrameAvailable() → Flutter                       │
│  • Flutter updates texture on next vsync                   │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│                    Web (WASM)                              │
├────────────────────────────────────────────────────────────┤
│ FrontendRenderer Web Worker (pthread emulation)            │
│  • RenderFrame() called from JS requestAnimationFrame     │
│  • Updates scene (tiles, overlays)                         │
│  • WebGL render calls to framebuffer texture               │
│  • Calls JS callback → signals frame ready                 │
│                                                            │
│ Main JS Thread Receives Frame-Ready Notification           │
│  • readPixels() from WebGL framebuffer                     │
│  • Copy to Canvas via putImageData()                       │
│  • Or: Direct WebGL texture to canvas (future)            │
│                                                            │
│ Flutter (Dart/JS) Updates Canvas Texture                   │
│  • Flutter's HTML Renderer samples Canvas                  │
│  • Or: HtmlElementView wraps Canvas directly               │
└────────────────────────────────────────────────────────────┘
```

### WebGL Framebuffer Setup

```cpp
// AgusWebGlContextFactory implementation
void AgusWebGlContextFactory::CreateFramebufferForSize(
    int width, int height) {
  // Get WebGL context (exposed by Emscripten)
  auto* gl = (WebGLRenderingContext*)emscripten_webgl_get_current_context();
  
  // Create framebuffer for off-screen rendering
  GLuint fbo;
  glGenFramebuffers(1, &fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, fbo);
  
  // Color texture (for CoMaps to render into)
  GLuint colorTex;
  glGenTextures(1, &colorTex);
  glBindTexture(GL_TEXTURE_2D, colorTex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 
               0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, 
                         GL_TEXTURE_2D, colorTex, 0);
  
  // Depth texture for 3D rendering
  GLuint depthTex;
  glGenTextures(1, &depthTex);
  glBindTexture(GL_TEXTURE_2D, depthTex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, width, height,
               0, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, nullptr);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                         GL_TEXTURE_2D, depthTex, 0);
  
  // Verify completeness
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    throw std::runtime_error("Framebuffer not complete");
  }
  
  m_fbo = fbo;
  m_colorTex = colorTex;
  m_depthTex = depthTex;
}
```

### Frame Readback and Canvas Update

```javascript
// In Dart/JavaScript bridge
function renderFrame() {
  // Call C++ RenderFrame() in WASM
  Module._agus_render_frame();
  
  // Read pixels from WebGL
  const gl = Module.ctx;  // WebGL context
  const width = Module.surfaceWidth;
  const height = Module.surfaceHeight;
  
  const pixels = new Uint8ClampedArray(width * height * 4);
  gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
  
  // Convert to ImageData (RGBA format, ready for canvas)
  const imageData = new ImageData(pixels, width, height);
  
  // Draw to canvas
  const canvas = document.getElementById('map-canvas');
  const ctx = canvas.getContext('2d');
  ctx.putImageData(imageData, 0, 0);
  
  // Or update Flutter texture
  flutter.sendMessageToFlutter({
    type: 'frame_ready',
    pixelsPtr: pixels.byteOffset,  // Pointer to WASM linear memory
    width, height
  });
}

// Request next frame
requestAnimationFrame(renderFrame);
```

### Alternative: OffscreenCanvas + WebWorker

For better performance (avoids main thread blocking):

```javascript
// Main thread
const offscreenCanvas = canvas.transferControlToOffscreen();

// Send to Worker
worker.postMessage({
  cmd: 'init',
  canvas: offscreenCanvas
}, [offscreenCanvas]);

// Worker thread
let wasmModule;
self.onmessage = async (e) => {
  if (e.data.cmd === 'init') {
    const canvas = e.data.canvas;
    const gl = canvas.getContext('webgl2');
    
    // Initialize WASM engine with this canvas
    wasmModule = await loadWasm(gl);
    
    // Main render loop
    function renderLoop() {
      wasmModule._agus_render_frame();
      readAndBlitToCanvas();
      requestAnimationFrame(renderLoop);
    }
    renderLoop();
  }
};
```

**Pros:** Rendering doesn't block Flutter UI  
**Cons:** Added complexity with OffscreenCanvas browser support


## API Surface & Dart-WASM Bridge

### Current FFI API Review

All platforms use the same Dart FFI interface:

```dart
// agus_maps_flutter.dart
void init(String apkPath, String storagePath)
void initWithPaths(String resourcePath, String writablePath)
void loadMap(String path)
int registerSingleMap(String fullPath)
void setView(double lat, double lon, int zoom)
void touch(int type, int id1, float x1, float y1, int id2, float x2, float y2)
void scale(double factor, double pixelX, double pixelY, int animated)
void scroll(double distanceX, double distanceY)
// ... etc
```

### WASM Bridging with dart:js

```dart
// agus_maps_flutter_wasm.dart (new file, web-only)
@JS('window.agusMapModule')
external dynamic get wasmModule;

Future<void> initWithPaths(String resourcePath, String writablePath) async {
  // For WASM, paths are virtual FS mount points
  // e.g., "/comaps/engine" and "/comaps/maps"
  await js.context.callMethod('agusInitWithPaths',
      [resourcePath, writablePath]);
}

void registerSingleMap(String fullPath) {
  // Dart→JS call to fetch from IndexedDB and mount
  js.context.callMethod('agusRegisterMap', [fullPath]);
}

void touch(int type, int id1, double x1, double y1, int id2, double x2, double y2) {
  // Direct passthrough to WASM
  wasmModule.comaps_touch(type, id1, x1, y1, id2, x2, y2);
}

// Dart message from JavaScript
void _setupFrameCallback() {
  js.context['agusFrameReady'] = allowInterop((Uint8List pixels, int width, int height) {
    // Update Flutter texture
    _mapController._onFrameReady(pixels, width, height);
  });
}
```

### JavaScript Module Interface

```javascript
// agus-maps-wasm.js
window.agusMapModule = {
  // Initialized by Emscripten with WASM module
  _module: null,
  
  async init() {
    // Load WASM module
    this._module = await createModule({
      canvas: document.getElementById('map-canvas'),
      // Emscripten configuration
      PTHREAD_POOL_SIZE: 2,
      ALLOW_MEMORY_GROWTH: 1,
      print: console.log,
      printErr: console.error
    });
    
    // Setup IndexedDB for maps
    window.mapStorage = new MapStorage();
    await window.mapStorage.init();
  },
  
  async agusInitWithPaths(resourcePath, writablePath) {
    // Mount bundled engine data
    // await extractBundledData(resourcePath);
    
    // Initialize WASM engine
    this._module._comaps_init_paths(
      this._module.allocateUTF8(resourcePath),
      this._module.allocateUTF8(writablePath)
    );
  },
  
  async agusRegisterMap(fullPath) {
    // Fetch from IndexedDB
    const basename = fullPath.split('/').pop();
    const blob = await window.mapStorage.getMap(basename);
    
    if (!blob) {
      throw new Error(`Map not found in storage: ${basename}`);
    }
    
    // Write to Emscripten FS
    const data = new Uint8Array(await blob.arrayBuffer());
    FS.writeFile(fullPath, data);
    
    // Register with engine
    this._module._comaps_register_single_map(
      this._module.allocateUTF8(fullPath)
    );
  },
  
  comaps_touch: (type, id1, x1, y1, id2, x2, y2) => {
    window.agusMapModule._module._comaps_touch(type, id1, x1, y1, id2, x2, y2);
  },
  
  comaps_set_view: (lat, lon, zoom) => {
    window.agusMapModule._module._comaps_set_view(lat, lon, zoom);
  },
  
  // ... other API methods
};

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
  window.agusMapModule.init().catch(console.error);
});
```

### Dart-JavaScript Interop

```dart
// Map touch events to WASM
void _handlePointerEvent(PointerEvent event) {
  if (event is PointerDownEvent) {
    js.context.callMethod('agusMapModule.comaps_touch', [
      1, // TOUCH_DOWN
      event.pointer, event.position.dx, event.position.dy,
      -1, 0, 0 // No second touch
    ]);
  } else if (event is PointerMoveEvent) {
    js.context.callMethod('agusMapModule.comaps_touch', [
      2, // TOUCH_MOVE
      event.pointer, event.position.dx, event.position.dy,
      -1, 0, 0
    ]);
  } else if (event is PointerUpEvent) {
    js.context.callMethod('agusMapModule.comaps_touch', [
      3, // TOUCH_UP
      event.pointer, event.position.dx, event.position.dy,
      -1, 0, 0
    ]);
  }
}
```


## Implementation Phases

### Phase 1: MVP - Core WASM Engine (3-4 weeks)

**Goals:**
- Compile CoMaps to WASM with Emscripten
- WebGL rendering with CPU-mediated readPixels
- Bundle engine data and 1-2 maps
- Basic offline rendering in browser

**Deliverables:**
- Dart build tool WASM target (planned) - Emscripten compilation
- `src/AgusWebGlContextFactory.cpp` - WebGL backend
- `web/` directory with example HTML + JS
- WASM binary + bundled assets (~150 MB)
- Patch updates for WASM platform detection

**Testing:**
- Render maps in Chrome/Firefox/Safari
- Verify offline capability after initial load
- Basic touch/pan/zoom interaction

### Phase 2: Asset Management (2 weeks)

**Goals:**
- IndexedDB persistent storage
- Service Worker caching
- Dynamic map registration
- Storage quota awareness

**Deliverables:**
- `web/lib/map-storage.js` - IndexedDB wrapper
- `web/service-worker.js` - Offline caching
- `lib/mwm_storage_web.dart` - Web-specific storage tracker
- Download UI for additional maps

**Testing:**
- Offline launch (no network)
- Simulate quota exhaustion
- Clear cache and reload

### Phase 3: Performance & Polish (2-3 weeks)

**Goals:**
- Optimize binary size (LTO, strip unused symbols)
- WebGL texture-to-canvas improvements
- OffscreenCanvas for non-blocking render
- Hot reload support during development

**Deliverables:**
- Size-optimized WASM binary (~2.5 MB gzipped)
- Performance profiling and bottleneck analysis
- Flutter web example with map widget
- Documentation update

### Phase 4: Production Features (Optional, post-MVP)

**Goals:**
- S3/CDN mirror integration for map downloads
- Persistent MWM version tracking
- Auto-update checks
- Search and routing (if not already in CoMaps WASM)

**Deliverables:**
- MirrorService web adaptation
- Map update notifications
- Graceful degradation if network fails


## Risk Assessment

### High-Risk Areas

#### 1. **Memory Management & Garbage Collection**

**Risk:** WASM heap fragmentation with large MWM files (50+ MB).

**Mitigation:**
- Pre-allocate mmap buffers in Emscripten MEMFS
- Monitor heap growth with Emscripten profiling tools
- Consider memory pooling for tile cache

**Test:** Load World.mwm + render high-zoom view. Monitor JS heap in DevTools.

#### 2. **Threading Model Mismatch**

**Risk:** Emscripten pthreads has limitations (SharedArrayBuffer, browser compatibility).

**Mitigation:**
- Start with single-threaded mode (requestAnimationFrame only)
- Upgrade to Web Workers if performance needs it
- Document pthread limitations clearly

**Test:** Run on iOS Safari and Android Firefox (limited SAB support).

#### 3. **Browser API Quotas**

**Risk:** IndexedDB quota varies by browser (50 MB - 2 GB). Users hit quota with multiple regions.

**Mitigation:**
- Start with 2-3 representative maps (World + 1-2 regions)
- Show storage usage UI
- Implement LRU eviction policy
- Document quota requirements per region

**Test:** Load 100+ MB of maps, verify eviction works.

#### 4. **Platform-Specific Graphics Quirks**

**Risk:** WebGL behavior differs across browsers (ANGLE on Windows, Metal on macOS, etc.).

**Mitigation:**
- Test on multiple platforms: Chrome, Firefox, Safari, Edge
- Use WebGL 2.0 (good support since 2017)
- Avoid vendor-specific extensions initially
- Monitor WebGL error logs

**Test:** Render same scene on Windows/Mac/Linux browsers, compare output.

#### 5. **Binary Size Bloat**

**Risk:** Adding WASM binary, ICU, fonts, etc. → 200+ MB total download.

**Mitigation:**
- Lazy-load maps on demand (not bundled)
- Separate WASM binary from assets
- Use brotli compression (20% smaller than gzip)
- Consider tree-shaking unused CoMaps features

**Test:** Measure transfer time on slow 3G, verify under 10 seconds.

#### 6. **Service Worker Update Strategy**

**Risk:** Old cached WASM binaries cause compatibility issues.

**Mitigation:**
- Version service worker cache by release (agus-maps-flutter-vX.Y.Z)
- Implement cache versioning and cleanup
- Show "reload required" prompt if binary changes
- Clear old caches on install

**Test:** Deploy new binary version, verify SW automatically updates.

### Medium-Risk Areas

#### 7. **File I/O Performance**

**Risk:** Emscripten IDBFS→MEMFS overhead makes map loading slow.

**Mitigation:**
- Profile with Emscripten tools
- Keep frequently-accessed files in MEMFS (tile cache)
- Lazy-load rarely-used data
- Consider custom file system layer

**Test:** Benchmark: load Gibraltar.mwm, time to first render.

#### 8. **Touch Event Handling Latency**

**Risk:** JavaScript→WASM roundtrip adds input lag (vs native 1-2ms).

**Mitigation:**
- Profile input→render latency
- Optimize hot path (touch handler → C++ → render)
- Use requestAnimationFrame for smooth updates
- Consider Web Workers to avoid main thread blocking

**Test:** Measure from pointer down to frame update (target: <16ms for 60 FPS).

#### 9. **Search & Transliteration**

**Risk:** ICU (1.3 MB) + transliteration overhead in WASM.

**Mitigation:**
- Profile ICU memory usage
- Consider subset of ICU (common scripts only)
- Defer transliteration to Dart if too slow
- Document when transliteration works/doesn't

**Test:** Search for non-Latin text (e.g., Russian, Chinese), verify results.

### Low-Risk Areas

#### 10. **Shader Compilation**

**Risk:** WASM shader compilation slower than native.

**Mitigation:**
- CoMaps pre-compiles shaders to binary (SPIR-V)
- Emscripten can load these directly as WebGL shaders
- No runtime compilation needed

**Test:** Verify shader load time <100ms on slow device.


## Success Criteria

### MVP (Phase 1) Success

- [ ] WASM binary compiles and loads in browser
- [ ] Maps render with WebGL without errors
- [ ] Offline rendering works (no network after initial load)
- [ ] Basic interactions work: pan, zoom, rotate
- [ ] Frame rate: >30 FPS on desktop, >20 FPS on mobile
- [ ] Verified on Chrome, Firefox, Safari (latest versions)
- [ ] Documentation: PLAN-WASM.md (this file) + code comments

### Phase 2 (Asset Management) Success

- [ ] IndexedDB storage works and persists across page reloads
- [ ] Service Worker caches assets and enables offline mode
- [ ] MwmStorage tracks web maps with metadata
- [ ] Storage quota UI shows usage percentage
- [ ] Can delete/clear cached maps manually
- [ ] New maps can be registered dynamically (from downloads or file input)

### Phase 3 (Performance & Polish) Success

- [ ] WASM binary < 3 MB gzipped
- [ ] Total bundle < 200 MB (with bundled maps)
- [ ] Offline load time < 5 seconds (after SW caching)
- [ ] Pan/zoom frame rate: 45+ FPS on desktop, 30+ FPS on mobile
- [ ] Touch input latency < 50ms perceived delay
- [ ] No console errors or warnings in normal use

### Phase 4 (Production) Success

- [ ] MirrorService fetches maps from CDN
- [ ] Maps auto-update when new versions available
- [ ] Search results work with transliteration
- [ ] Graceful offline fallback if CDN unavailable
- [ ] Documented in API docs and examples


## Recommendations & Next Steps

### Immediate Actions (Week 1)

1. **Validate Emscripten Compatibility**
   - Test compiling a simple CoMaps app with Emscripten
   - Identify missing/problematic dependencies
   - Build proof-of-concept WebGL context

2. **Assess Binary Size**
   - Compile with `-Oz` optimization
   - Measure uncompressed and gzipped sizes
   - Identify largest components (libraries)

3. **Create WASM Build Target**
  - Dart build tool WASM target with Emscripten CMake
  - Set up cross-platform (macOS/Linux support)
  - Document build requirements

### Next Phases (Weeks 2-4)

4. **Implement WebGL Context Factory**
   - `src/AgusWebGlContextFactory.cpp`
   - Frame readback and Canvas update
   - Platform detection patches

5. **Asset Bundling & Extraction**
   - Create tarball of engine data files
   - Implement Emscripten IDBFS mounting
   - Test offline rendering

6. **Create Web Example**
   - HTML + CSS for map container
   - JavaScript module for WASM initialization
   - Flutter web example app

### Decision Points

**Q1: Bundle all maps or lazy-load?**
- **Recommended:** Bundle World + WorldCoasts for MVP
- Add dynamic loading in Phase 2

**Q2: Single-threaded or Web Workers?**
- **Recommended:** Start single-threaded (requestAnimationFrame)
- Benchmark before deciding to add complexity

**Q3: Direct WASM updates to Canvas or through Flutter?**
- **Recommended:** Direct Canvas updates initially
- Flutter texture integration if performance issues arise

**Q4: IndexedDB vs Service Worker caching?**
- **Recommended:** Both
  - IndexedDB for large MWM files (per-file management)
  - Service Worker for static assets (app.js, .wasm)


## Appendix: Platform Pattern Mapping

### How Existing Platform Patterns Apply to WASM

| Pattern | iOS/macOS | Android | Windows/Linux | WASM |
|---------|-----------|---------|---------------|------|
| **Graphics API** | Metal | OpenGL ES | OpenGL/D3D11 | WebGL 2.0 |
| **Surface Creation** | CVPixelBuffer | ANativeWindow | HWND/X11 | Canvas |
| **Frame Transfer** | IOSurface (GPU) | SurfaceTexture (GPU) | glReadPixels (CPU) | readPixels (CPU) |
| **Thread Model** | GCD dispatch | JNI callback | PostMessage | requestAnimationFrame |
| **File Access** | NSFileManager | Android Storage | POSIX FS | Emscripten VFS |
| **Event Dispatch** | UIView touches | onTouchEvent | WM_TOUCH | PointerEvent |
| **Memory Management** | Objective-C ARC | JVM GC | C++ new/delete | Emscripten malloc |

**Key Insight:** WASM follows the Windows/Linux pattern (CPU-mediated readPixels) more than iOS/Android, but applies modern web standards (Canvas, Service Workers, IndexedDB).


## Conclusion

Web support via WASM is **technically feasible and pragmatic** for the Agus Maps Flutter plugin. The approach trades zero-copy GPU efficiency for browser portability and offline capability, which is appropriate for web.

**Core strengths:**
- Reuses 95% of existing CoMaps C++ code
- No custom native code required
- Offline-first design with bundled maps
- Graceful degradation with dynamic downloads

**Core challenges:**
- WASM binary size (5-8 MB uncompressed)
- Memory constraints for large MWM files
- Service Worker/IndexedDB browser compatibility
- Performance tuning for reasonable FPS

**Recommendation:** Proceed with MVP implementation (Phase 1) as a proof-of-concept. Success criteria are well-defined and achievable within 3-4 weeks.


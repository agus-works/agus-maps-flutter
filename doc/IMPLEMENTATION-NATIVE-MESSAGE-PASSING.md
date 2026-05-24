# Native Message Passing Implementation

This document describes **all message‑passing paths** between Dart and native code in Agus Maps Flutter. It covers:

- **Typed platform channels (Pigeon)** for structured, low‑frequency events and host calls.
- **C FFI** entry points for high‑frequency or performance‑critical calls.
- **Per‑platform native implementations** (Android, iOS, macOS, Windows, Linux).
- **Data models** (Place Page payloads) and lifecycle.
- **Threading, ownership, and error handling** rules.

> Scope: This doc focuses on message passing and data flow. Rendering architecture is documented in GUIDE.md and platform‑specific docs.

---

## Document Structure

This document uses a **dual‑audience format**:

- **Non‑Technical Summary** sections explain concepts in plain language for product managers, designers, and other stakeholders.
- **Technical Deep Dive** sections provide implementation details for developers.

Look for these headings within each major section.

---

## 1. Overview: Two Message‑Passing Layers

### 1.1 Non‑Technical Summary

When the Flutter app needs to talk to the underlying map engine (written in C++), it uses two different "languages":

1. **Pigeon** — Like sending a detailed letter. Used for complex information (place names, addresses, coordinates). Slower but very reliable and organized.

2. **FFI (Foreign Function Interface)** — Like a direct phone call. Used for rapid‑fire interactions (finger touches, zooming). Very fast but only handles simple data.

**Why two methods?** Different tasks need different tools. You wouldn't use a formal letter to say "I'm touching the screen right now" — that needs to be instant. But you would use a formal letter to send detailed place information with 20+ fields.

### 1.2 Technical Deep Dive

Agus Maps Flutter uses **two distinct layers**:

1. **Pigeon (platform channels):**
   - Strongly‑typed, structured data
   - Low‑frequency notifications and control calls
   - Example: map ready, render state changes, place page payloads

2. **FFI (C ABI):**
   - High‑frequency or performance‑critical calls
   - Direct, synchronous calls into native code
   - Example: touch events, map camera changes, render lifecycle

**Why two layers?**
- Pigeon gives safe, typed, cross‑platform messaging for event‑like and request/response APIs.
- FFI gives minimal overhead for real‑time interactions.

---

## 2. Pigeon: Typed Platform Messaging

### 2.1 Source Definition

The authoritative Pigeon API is defined in:

- pigeons/agus_maps_api.dart

Generated files are checked in and must be regenerated from this source.

### 2.2 Generated Files

Pigeon generates platform‑specific bindings in:

- lib/src/agus_maps_api.g.dart
- android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsApi.java
- ios/agus_maps_flutter/Sources/agus_maps_flutter/AgusMapsApi.g.swift
- macos/agus_maps_flutter/Sources/agus_maps_flutter/AgusMapsApi.g.swift
- windows/agus_maps_api.g.h
- windows/agus_maps_api.g.cpp
- linux/agus_maps_api.g.h
- linux/agus_maps_api.g.cc

### 2.3 Pigeon APIs and Data Models

#### 2.3.1 Data Models

**PlacePageFeatureId**
- Purpose: Stable feature identifier for a place page.
- Fields:
  - mwmName (String)
  - mwmVersion (int64)
  - index (int64)

**PlacePageCoordinates**
- Purpose: Formatted coordinate variants.
- Fields (nullable Strings):
  - decimal, dms, osm, olc, utm, mgrs

**PlacePageIntMetadataEntry**
- Purpose: Integer‑keyed metadata entry.
- Fields:
  - key (int64)
  - value (String)

**PlacePageStringMetadataEntry**
- Purpose: String‑keyed metadata entry.
- Fields:
  - key (String)
  - value (String)

**PlacePageData**
- Purpose: Structured place page payload.
- Fields:
  - featureId (PlacePageFeatureId)
  - objectType (int64)
  - openingMode (int64)
  - title (String)
  - secondaryTitle (String)
  - subtitle (String)
  - address (String)
  - lat (double)
  - lon (double)
  - wikiDescriptionHtml (String)
  - roadType (int64)
  - isRoutePoint (bool)
  - coordinates (PlacePageCoordinates)
  - rawTypes (List<String>)
  - metadata (List<PlacePageIntMetadataEntry>)
  - metadataTags (List<PlacePageStringMetadataEntry>)
  - bookmarkId (int64?, optional)
  - bookmarkCategoryId (int64?, optional)
  - trackId (int64?, optional)

These models replace any prior string‑based JSON payloads to ensure strong typing and cross‑platform consistency.

#### 2.3.2 Host API (Native implements, Dart calls)

**AgusMapsHostApi** (Pigeon)

- extractMap(String assetPath) → String
  - Extracts map assets to a platform‑specific writable directory.

- extractDataFiles() → String
  - Extracts CoMaps data files to a writable directory.

- getApkPath() → String
  - Android: APK path
  - Desktop: executable directory

- createMapSurface(CreateMapSurfaceRequest) → int
  - Creates a native rendering surface and returns a texture ID.

- resizeMapSurface(ResizeMapSurfaceRequest) → bool
  - Resizes the active native surface.

- destroyMapSurface() → bool
  - Tears down the surface and render resources.

- getCurrentPlacePage() → PlacePageData?
  - Returns the current place page payload if available.

- clearPlacePageSelection() → bool
  - Clears the current place page selection.

#### 2.3.3 Flutter API (Dart implements, native calls)

**AgusMapsFlutterApi** (Pigeon)

- onMapReady(int surfaceId)
  - Emitted when the surface is ready and usable.

- onRenderStateChanged(RenderState state, int? surfaceId)
  - Emitted when rendering state changes (active/idle).

- onPlacePageChanged(PlacePageData? placePage)
  - Emitted when the native selection changes.

---

## 3. Dart‑Side Wiring

### 3.1 Event Streams

In lib/agus_maps_flutter.dart, Pigeon events are surfaced as broadcast streams:

- AgusMapsFlutterEvents.onMapReady
- AgusMapsFlutterEvents.onRenderStateChanged
- AgusMapsFlutterEvents.onPlacePageChanged

A handler class wires the Pigeon FlutterApi into these streams:

- _AgusMapsFlutterApiHandler

### 3.2 Place Page Localization Layer

`PlacePageLocalization` localizes parts of the structured payload after receipt:

- Subtitle localization via type translations
- Metadata tag localization via Localizable.strings

This runs in `_localizePlacePage` and is applied both to:

- onPlacePageChanged events
- getCurrentPlacePage responses

### 3.3 Public API Calls

Dart calls into the host API through:

- `AgusMapsHostApi` (Pigeon)

Examples:

- `createMapSurface` → native
- `resizeMapSurface` → native
- `destroyMapSurface` → native
- `getCurrentPlacePage` → native
- `clearPlacePageSelection` → native

---

## 4. FFI (C ABI) Message Passing

### 4.1 C API Surface

The C‑ABI is defined in:

- src/agus_maps_flutter.h

These functions are exposed to Dart via dart:ffi and to native hosts internally.

Key categories:

**Lifecycle and Init**
- comaps_init
- comaps_init_paths
- comaps_shutdown

**Map Surface & Rendering**
- agus_native_create_surface
- agus_native_on_size_changed
- agus_native_set_visual_scale
- agus_native_on_surface_destroyed
- agus_render_frame
- agus_set_frame_ready_callback

**Input and Camera**
- comaps_touch
- comaps_set_view
- comaps_scale
- comaps_scroll

**Map Asset Management**
- comaps_load_map_path
- comaps_register_single_map
- comaps_register_single_map_with_version
- comaps_deregister_map

**Diagnostics**
- comaps_debug_list_mwms
- comaps_debug_check_point
- comaps_get_registered_maps_count

**Place Page (Structured)**
- comaps_place_page_has_data
- comaps_place_page_copy
- comaps_place_page_free
- comaps_place_page_clear_selection

### 4.2 Ownership and Memory Rules

- `comaps_place_page_copy` returns a **heap‑allocated snapshot**.
- The caller must invoke `comaps_place_page_free` to release it.
- All string fields inside the struct are owned by the snapshot and freed by `comaps_place_page_free`.
- The snapshot is immutable for the caller’s lifetime.

### 4.3 Place Page Struct Layout

The C struct used across platforms is:

- AgusPlacePageData

It contains:
- Feature ID
- Titles, subtitle, address
- Coordinates
- Raw types
- Metadata entries
- Optional bookmark and track IDs

The native platform code uses this struct to convert into Pigeon models.

---

## 5. Per‑Platform Native Implementations

### 5.1 Android

**Pigeon Host API:**
- Implemented in Android plugin (AgusMapsFlutterPlugin.java)
- `getCurrentPlacePage` calls into JNI to fetch structured Pigeon objects
- `clearPlacePageSelection` calls native FFI

**FFI/Native Entry:**
- C++ in src/agus_maps_flutter.cpp
- JNI wrapper creates Java Pigeon PlacePageData
- `comaps_place_page_copy` uses current Framework selection

**Data Flow (Place Page):**
1. Dart calls getCurrentPlacePage.
2. Pigeon Host API calls JNI method nativeGetCurrentPlacePage.
3. Native builds AgusPlacePageData snapshot.
4. JNI converts to Java Pigeon PlacePageData.
5. Dart receives PlacePageData.

### 5.2 iOS

**Pigeon Host API:**
- AgusMapsFlutterPlugin.swift
- Uses comaps_place_page_copy and converts to Swift Pigeon types

**Native C++:**
- ios/agus_maps_flutter/Sources/agus_maps_flutter_native/agus_maps_flutter_ios.mm
- Builds AgusPlacePageData snapshot from CoMaps place page info

**Data Flow:**
1. Dart calls getCurrentPlacePage.
2. Swift host API calls comaps_place_page_copy.
3. Swift converts to PlacePageData.
4. Dart receives PlacePageData.

### 5.3 macOS

Same architecture as iOS:

- Swift host API in macos/agus_maps_flutter/Sources/agus_maps_flutter/AgusMapsFlutterPlugin.swift
- Native C++ in macos/agus_maps_flutter/Sources/agus_maps_flutter_native/agus_maps_flutter_macos.mm
- Uses comaps_place_page_copy → Swift conversion

### 5.4 Linux

**Pigeon Host API:**
- linux/agus_maps_flutter_plugin.cc
- Implements handlers using gobject Pigeon types

**Data Flow:**
1. Dart calls getCurrentPlacePage.
2. Linux plugin checks comaps_place_page_has_data.
3. Calls comaps_place_page_copy.
4. Converts to gobject PlacePageData.
5. Responds over Pigeon channel.

### 5.5 Windows

**Pigeon Host API:**
- windows/agus_maps_flutter_plugin.cpp
- `GetCurrentPlacePage` uses FFI symbol lookup for place page APIs
- Converts AgusPlacePageData into Pigeon PlacePageData
- `ClearPlacePageSelection` calls FFI symbol

**Data Flow:**
1. Dart calls getCurrentPlacePage.
2. Windows host API loads FFI symbols (comaps_place_page_*).
3. Calls comaps_place_page_copy and converts to PlacePageData.
4. Dart receives PlacePageData.

---

## 6. Error Handling & Nullability

- Host APIs return null place page data when unavailable.
- Errors in native are surfaced as Pigeon errors where appropriate.
- Dart defensive checks:
  - If comaps_place_page_has_data == 0, return null
  - PlacePageData localization is best‑effort; missing strings are tolerated

---

## 7. Threading and Performance Notes

- Pigeon calls run on the platform channel threads (engine managed).
- FFI calls are synchronous on the calling isolate.
- High‑frequency or time‑sensitive operations (touch input, camera updates) use FFI.
- Low‑frequency or structured data (events, place page payloads) use Pigeon.

---

## 8. Extending Message Passing

### 8.1 Adding a New Pigeon API

1. Update pigeons/agus_maps_api.dart
2. Regenerate Pigeon outputs
3. Implement the Host API on all platforms
4. Update Dart wiring and public API

### 8.2 Adding a New FFI API

1. Add C function to src/agus_maps_flutter.h
2. Implement platform‑specific backend in src/agus_maps_flutter*.cpp
3. Regenerate Dart FFI bindings (ffigen)
4. Call from Dart

---

## 9. Data Transfer Validation Audit

> **Last audited:** January 2026

This section documents the results of a comprehensive audit ensuring all native↔Dart data flows use proper serialization mechanisms (Pigeon or StandardMessageCodec) rather than manual string concatenation or ad‑hoc serialization.

### 9.1 Non‑Technical Summary

**What we checked:** We reviewed all code that moves data between Dart (Flutter) and native platforms (Android, iOS, macOS, Windows, Linux) to ensure it follows best practices.

**What we found:** ✅ **All native↔Dart communication is properly implemented.**

- Complex data (like place information with names, coordinates, metadata) uses **Pigeon**—a code generator that creates type‑safe communication channels.
- Simple, frequent operations (like touch events or zoom) use **FFI**—a direct, fast connection to native code that only passes simple values like numbers.
- JSON is used **only** for appropriate purposes: downloading data from the internet and saving preferences locally—never for passing data between Dart and native code.

**Why this matters:** Proper data serialization prevents bugs, improves performance, and makes the code maintainable. Manual string manipulation for data transfer is error‑prone and hard to debug.

### 9.2 Technical Deep Dive

#### 9.2.1 Audit Scope

**Files analyzed:**

| Directory | Files | Purpose |
|-----------|-------|---------|
| `src/` | `agus_maps_flutter.cpp`, `agus_maps_flutter.h`, platform‑specific `.mm`/`.cpp` | Native C/C++ implementation |
| `lib/` | `agus_maps_flutter.dart`, `*_bindings_generated.dart`, `mirror_service.dart`, `mwm_storage.dart`, `src/*.dart` | Dart plugin code |
| `pigeons/` | `agus_maps_api.dart` | Pigeon API definitions |
| Platform dirs | Android `.java`, iOS/macOS `.swift`, Windows/Linux `.cpp`/`.cc` | Platform‑specific Pigeon implementations |

#### 9.2.2 Native↔Dart Communication Patterns

**Pattern 1: Pigeon for Structured Data** ✅

All complex structured data transfers use Pigeon‑generated code:

```
┌─────────────────────┐     StandardMessageCodec      ┌─────────────────────┐
│   Dart (Flutter)    │ ◄──────────────────────────► │   Native Platform   │
│                     │        (Binary, typed)        │                     │
│  PlacePageData      │                               │  AgusMapsHostApi    │
│  RenderState        │                               │  implementation     │
│  CreateMapSurface   │                               │                     │
└─────────────────────┘                               └─────────────────────┘
```

**Pattern 2: FFI for High‑Frequency Primitives** ✅

Touch events, camera movements, and render triggers use direct FFI with primitive types only:

```
┌─────────────────────┐      Direct C ABI call        ┌─────────────────────┐
│   Dart (Flutter)    │ ─────────────────────────────►│   Native C/C++      │
│                     │    (int, double, pointer)     │                     │
│  comaps_touch(...)  │                               │  Touch handler      │
│  comaps_scale(...)  │                               │  Camera control     │
│  comaps_scroll(...) │                               │  Render loop        │
└─────────────────────┘                               └─────────────────────┘
```

#### 9.2.3 JSON Usage Analysis

JSON encoding/decoding was found in specific files. **None of these involve native↔Dart communication:**

| File | Usage | Verdict |
|------|-------|---------|
| `lib/mirror_service.dart` | Parsing HTTP responses from CDN metaserver | ✅ Appropriate |
| `lib/mwm_storage.dart` | Persisting MWM metadata to SharedPreferences | ✅ Appropriate |
| `lib/src/cdn_utils.dart` | Parsing `countries.txt` from CDN | ✅ Appropriate |

**Key distinction:** These JSON operations handle:
- **Network responses** from external HTTP APIs
- **Local persistence** via SharedPreferences

They do **not** serialize data for Dart↔native platform channel communication.

#### 9.2.4 String Operations Analysis

String parsing operations were found for:

| Location | Operation | Purpose | Verdict |
|----------|-----------|---------|---------|
| `lib/agus_maps_flutter.dart` | Subtitle parsing | Localizing UI labels after Pigeon delivery | ✅ Post‑receipt processing |
| `lib/agus_maps_flutter.dart` | `.strings` file parsing | Loading localization assets | ✅ Asset loading |
| `lib/agus_maps_flutter.dart` | Version string parsing | Parsing YYMMDD snapshot versions | ✅ Application logic |

**None of these are workarounds for native communication.** They operate on data already received via proper channels.

#### 9.2.5 Validation Results

| Communication Path | Mechanism | Manual Serialization? | Status |
|--------------------|-----------|----------------------|--------|
| PlacePageData native→Dart | Pigeon | No | ✅ |
| RenderState native→Dart | Pigeon | No | ✅ |
| MapReady native→Dart | Pigeon | No | ✅ |
| Surface creation Dart→native | Pigeon | No | ✅ |
| Touch events Dart→native | FFI (primitives) | No | ✅ |
| Camera control Dart→native | FFI (primitives) | No | ✅ |
| Map registration Dart→native | FFI (C strings) | No | ✅ |

---

## 10. Dart Isolate Communication

> This section documents Dart‑to‑Dart isolate communication patterns used within the plugin. These are **internal to Dart** and do not involve native platform code.

### 10.1 Non‑Technical Summary

**What are isolates?** In Dart, isolates are like separate workers that can run code in parallel without blocking the main app. They're useful for heavy computations.

**Why document this here?** The plugin uses custom message classes (`_SumRequest`, `_SumResponse`) for isolate communication. This might be confused with native message passing, but it's entirely different:

- **Native message passing** = Dart ↔ Android/iOS/Windows/Linux/macOS
- **Isolate communication** = Dart ↔ Dart (within Flutter only)

**Current usage:** The plugin uses isolates for background tasks like asset extraction and file processing, keeping the UI responsive.

### 10.2 Technical Deep Dive

#### 10.2.1 Isolate Message Classes

Located in `lib/agus_maps_flutter.dart`:

```dart
/// Internal request for isolate computation
class _SumRequest {
  final SendPort responsePort;
  final String workPath;
  // ... other fields
}

/// Internal response from isolate computation
class _SumResponse {
  final bool success;
  final String? error;
  // ... other fields
}
```

#### 10.2.2 Why Not Pigeon?

Pigeon is for **platform channels** (Dart ↔ native). Dart isolate communication uses:

- `SendPort` / `ReceivePort` for message passing
- Standard Dart serialization (objects must be sendable across isolates)

These are fundamentally different mechanisms:

| Aspect | Pigeon (Platform Channels) | Dart Isolates |
|--------|---------------------------|---------------|
| Endpoints | Dart ↔ Native code | Dart ↔ Dart |
| Serialization | StandardMessageCodec | Dart's internal serialization |
| Thread model | Platform UI thread | Dart isolate threads |
| Use case | Cross‑platform APIs | Background computation |

#### 10.2.3 Current Isolate Operations

| Operation | Purpose | Input | Output |
|-----------|---------|-------|--------|
| Asset extraction | Unpack map data files | Path, asset bundle | Success/failure |
| File hashing | Compute checksums | File path | Hash value |
| Bulk registration | Register multiple MWMs | List of paths | Registration results |

#### 10.2.4 Best Practices Followed

1. **Message classes are private** (`_SumRequest`, `_SumResponse`)—not exposed in public API
2. **Minimal data transfer**—only essential fields cross isolate boundaries
3. **Error propagation**—failures in isolates are captured and returned to main isolate
4. **No shared mutable state**—isolates communicate only via messages

---

## 11. Architecture Diagram

### 11.1 Non‑Technical Summary

The diagram below shows how data flows in the plugin. Think of it as a map:

- **Green arrows** = Pigeon (safe, structured data like place information)
- **Blue arrows** = FFI (fast, simple data like touch coordinates)
- **Orange arrows** = Dart isolates (background work within Flutter)

### 11.2 Technical Deep Dive

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Flutter (Dart)                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  lib/agus_maps_flutter.dart                                          │   │
│  │    • AgusMap widget                                                  │   │
│  │    • PlacePageLocalization                                           │   │
│  │    • Event streams (onMapReady, onPlacePageChanged, etc.)           │   │
│  └──────────────────┬────────────────────────┬────────────────────────┘   │
│                     │                        │                             │
│         ┌───────────▼───────────┐   ┌───────▼───────────┐                 │
│         │  Pigeon Host API      │   │  FFI Bindings     │                 │
│         │  (lib/src/*.g.dart)   │   │  (*_generated.dart)│                │
│         └───────────┬───────────┘   └───────┬───────────┘                 │
│                     │                        │                             │
│  ┌──────────────────┼────────────────────────┼──────────────────────────┐ │
│  │ Isolates         │                        │                          │ │
│  │ ┌──────────────┐ │                        │                          │ │
│  │ │_SumRequest   │◄┼── Dart-to-Dart only    │                          │ │
│  │ │_SumResponse  │ │   (not native)         │                          │ │
│  │ └──────────────┘ │                        │                          │ │
│  └──────────────────┼────────────────────────┼──────────────────────────┘ │
└─────────────────────┼────────────────────────┼─────────────────────────────┘
                      │                        │
        StandardMessageCodec            Direct C ABI
        (binary, type-safe)          (primitives only)
                      │                        │
┌─────────────────────┼────────────────────────┼─────────────────────────────┐
│                     ▼                        ▼                             │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                      Native Platform Layer                          │  │
│  ├─────────────────────────────────────────────────────────────────────┤  │
│  │  Android    │  iOS/macOS   │  Windows      │  Linux                 │  │
│  │  (JNI)      │  (Swift)     │  (C++)        │  (GObject)             │  │
│  ├─────────────┴──────────────┴───────────────┴────────────────────────┤  │
│  │                                                                      │  │
│  │  Pigeon Operations (structured):           FFI Operations (fast):   │  │
│  │  • getCurrentPlacePage → PlacePageData     • comaps_touch           │  │
│  │  • createMapSurface → texture ID           • comaps_scale           │  │
│  │  • onPlacePageChanged ← event              • comaps_scroll          │  │
│  │  • onRenderStateChanged ← event            • comaps_set_view        │  │
│  │                                            • agus_render_frame      │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│                           Native Code (src/)                               │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  agus_maps_flutter.cpp  →  CoMaps Framework                         │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

### 11.3 Data Flow Summary Table

| Data Type | Direction | Mechanism | Latency | Example |
|-----------|-----------|-----------|---------|---------|
| Complex structs | Native → Dart | Pigeon | ~1-5ms | PlacePageData |
| Events | Native → Dart | Pigeon | ~1-5ms | onMapReady |
| Control requests | Dart → Native | Pigeon | ~1-5ms | createMapSurface |
| Touch input | Dart → Native | FFI | <0.1ms | comaps_touch |
| Camera control | Dart → Native | FFI | <0.1ms | comaps_scale |
| Render trigger | Dart → Native | FFI | <0.1ms | agus_render_frame |
| Background work | Dart → Dart | Isolate | varies | Asset extraction |

---

## 12. Reference Links

- GUIDE.md
- doc/IMPLEMENTATION-ANDROID.md
- doc/IMPLEMENTATION-IOS.md
- doc/IMPLEMENTATION-MACOS.md
- doc/IMPLEMENTATION-LINUX.md
- doc/IMPLEMENTATION-WIN.md

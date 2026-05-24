// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let nativeHeaderSearchPaths = [
    "../../SharedSrc",
    "../../ThirdParty/duckdb_include",
    "../../Frameworks/DuckDB.xcframework/ios-arm64/Headers",
    "../../Frameworks/DuckDB.xcframework/ios-arm64_x86_64-simulator/Headers",
    "../../ThirdParty/comaps",
    "../../ThirdParty/comaps/libs",
    "../../ThirdParty/comaps/3party/boost",
    "../../ThirdParty/comaps/3party/glm",
    "../../ThirdParty/comaps/3party",
    "../../ThirdParty/comaps/3party/utfcpp/source",
    "../../ThirdParty/comaps/3party/jansson/jansson/src",
    "../../ThirdParty/comaps/3party/jansson",
    "../../ThirdParty/comaps/3party/expat/expat/lib",
    "../../ThirdParty/comaps/3party/icu/icu/source/common",
    "../../ThirdParty/comaps/3party/icu/icu/source/i18n",
    "../../ThirdParty/comaps/3party/freetype/include",
    "../../ThirdParty/comaps/3party/harfbuzz/harfbuzz/src",
    "../../ThirdParty/comaps/3party/minizip/minizip",
    "../../ThirdParty/comaps/3party/pugixml/pugixml/src",
    "../../ThirdParty/comaps/3party/protobuf/protobuf/src",
    "../../Headers/comaps",
    "../../Headers/comaps/libs",
    "../../Headers/comaps/3party/boost",
    "../../Headers/comaps/3party/glm",
    "../../Headers/comaps/3party",
    "../../Headers/comaps/3party/utfcpp/source",
    "../../Headers/comaps/3party/jansson/jansson/src",
    "../../Headers/comaps/3party/jansson",
    "../../Headers/comaps/3party/expat/expat/lib",
    "../../Headers/comaps/3party/icu/icu/source/common",
    "../../Headers/comaps/3party/icu/icu/source/i18n",
    "../../Headers/comaps/3party/freetype/include",
    "../../Headers/comaps/3party/harfbuzz/harfbuzz/src",
    "../../Headers/comaps/3party/minizip/minizip",
    "../../Headers/comaps/3party/pugixml/pugixml/src",
    "../../Headers/comaps/3party/protobuf/protobuf/src",
]

let cSettings = nativeHeaderSearchPaths.map {
    CSetting.headerSearchPath($0)
} + [
    .define("PLATFORM_IPHONE", to: "1"),
    .define("DEBUG", to: "1", .when(configuration: .debug)),
    .define("RELEASE", to: "1", .when(configuration: .release)),
    .define("NDEBUG", to: "1", .when(configuration: .release)),
]

let cxxSettings = nativeHeaderSearchPaths.map {
    CXXSetting.headerSearchPath($0)
} + [
    .define("PLATFORM_IPHONE", to: "1"),
    .define("DEBUG", to: "1", .when(configuration: .debug)),
    .define("RELEASE", to: "1", .when(configuration: .release)),
    .define("NDEBUG", to: "1", .when(configuration: .release)),
    .unsafeFlags(["-fexceptions", "-frtti"]),
]

let linkerSettings: [LinkerSetting] = [
    .linkedFramework("Metal"),
    .linkedFramework("MetalKit"),
    .linkedFramework("CoreVideo"),
    .linkedFramework("CoreGraphics"),
    .linkedFramework("CoreFoundation"),
    .linkedFramework("QuartzCore"),
    .linkedFramework("UIKit"),
    .linkedFramework("Foundation"),
    .linkedFramework("Security"),
    .linkedFramework("SystemConfiguration"),
    .linkedFramework("CoreLocation"),
    .linkedLibrary("c++"),
    .linkedLibrary("z"),
    .linkedLibrary("sqlite3"),
    .unsafeFlags(["-ObjC"]),
]

let package = Package(
    name: "agus_maps_flutter",
    platforms: [
        .iOS("15.6"),
    ],
    products: [
        .library(name: "agus-maps-flutter", targets: ["agus_maps_flutter"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "agus_maps_flutter",
            dependencies: [
                "agus_maps_flutter_native",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/agus_maps_flutter",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: linkerSettings
        ),
        .target(
            name: "agus_maps_flutter_native",
            dependencies: [
                "AgusCoMaps",
                "AgusDuckDB",
            ],
            path: "Sources/agus_maps_flutter_native",
            publicHeadersPath: "include",
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            linkerSettings: linkerSettings
        ),
        .binaryTarget(
            name: "AgusCoMaps",
            path: "Frameworks/CoMaps.xcframework"
        ),
        .binaryTarget(
            name: "AgusDuckDB",
            path: "Frameworks/DuckDB.xcframework"
        ),
    ],
    cxxLanguageStandard: .cxx2b
)

# Documentation Audit

This audit records the `doc/**/*.md` inventory checked after the Swift Package
Manager, Metal shader packaging, macOS runtime, and macOS platform menu
lifecycle changes.

## Updated Documents

| Document | Why it applies |
| --- | --- |
| `doc/issues/ISSUE-swift-package-manager.md` | Primary issue record for plugin-owned iOS/macOS SwiftPM support, Apple FFI loading, Metal shader bundling, and build validation. |
| `doc/issues/ISSUE-macos-platform-menu-lifecycle.md` | New issue record for the responsive macOS platform menu lifecycle and `Agus Suite` menu behavior. |
| `doc/PLAN-SWIFT-PM.md` | Historical implementation plan now needs an implementation status snapshot. |
| `doc/IMPLEMENTATION-MACOS.md` | macOS source layout, SwiftPM runtime behavior, Metal toolchain requirement, app name, and platform menu lifecycle changed. |
| `doc/DART-HOOKS.md` | Apple build hook now treats Metal shader compilation as required and copies shader resources to SwiftPM directories. |
| `doc/BUILD-CONFIGURATION.md` | Apple builds now support CocoaPods and SwiftPM plugin integration paths for this plugin. |
| `doc/IMPLEMENTATION-CI-CD.md` | CI/local Apple build assumptions changed for SwiftPM resource copies and output validation. |
| `doc/IMPLEMENTATION-IOS.md` | Apple source layout moved from `ios/Classes` into the SwiftPM-compatible package tree. |
| `doc/UI-LAYOUT.md` | Responsive desktop/tablet/mobile layout now owns a stable macOS platform menu above the shell. |
| `doc/layouts/desktop/README.md` | Desktop layout adds the `Tools` platform menu while default macOS menus remain global. |
| `doc/KEYMAP-ARCHITECTURE.md` | `Cmd+Q`, `Cmd+,`, and `Cmd+F` now have native platform-menu entry points on macOS. |
| `doc/API.md` | Active platform-specific implementation paths moved to the new Apple package source trees. |
| `doc/COMMAND-BAR.md` | macOS platform menu entry points now share command/search/tool registries. |
| `doc/COMAPS-ASSETS.md` | Active Apple plugin source paths moved to the new package source trees. |
| `doc/IMPLEMENTATION-LOCALISATION.md` | Active macOS native source path moved to the new package source tree. |
| `doc/IMPLEMENTATION-NATIVE-MESSAGE-PASSING.md` | Active Pigeon and native bridge paths moved to the new package source trees. |
| `doc/IMPLEMENTATION-NAVIGATION.md` | Active Apple navigation bridge paths moved to the new package source trees. |
| `doc/IMPLEMENTATION-SEARCH.md` | Active Apple search bridge paths moved to the new package source trees. |
| `doc/RENDER-LOOP.md` | Active Apple render-loop source references moved to the new package source trees. |
| `doc/issues/ISSUE-macos-resize-white-screen.md` | Current file references moved to the new macOS package source tree. |
| `doc/issues/ISSUE-placepage-deep-copy.md` | Current iOS conversion source reference moved to the new package source tree. |
| `doc/schemas/PLAN-PROGRESS.md` | Current DuckDB Apple bridge source references moved to the new package source trees. |
| `doc/user-stories/shape-drawing-preview.md` | Current Apple drawing bridge references moved to the new package source trees. |
| `doc/user-stories/workbench-modal-tools.md` | The `Tools` menu is desktop-only and comes from the same workbench tool registry. |
| `doc/schemas/MANUAL-TESTING.md` | Manual macOS smoke now includes platform menu resize validation. |

## Reviewed Inventory

| Document | Applicability decision |
| --- | --- |
| `doc/API.md` | Applies; updated active Apple source paths. |
| `doc/ARCHITECTURE-ANDROID.md` | Reviewed; Android architecture did not change. |
| `doc/ARCHIVING.md` | Reviewed; archive workflow did not change. |
| `doc/BUILD-CONFIGURATION.md` | Applies; updated. |
| `doc/COMAPS-ASSETS.md` | Applies; updated active Apple source paths. |
| `doc/COMMAND-BAR.md` | Applies; documented macOS platform menu entry points into shared command/search/tool flows. |
| `doc/CONTRIBUTING.md` | Reviewed; no contributor workflow change beyond docs already covered by Dart hooks and CI. |
| `doc/COPYING.md` | Reviewed; licensing/copying behavior did not change. |
| `doc/DART-HOOKS.md` | Applies; updated. |
| `doc/DOCUMENTATION-AUDIT.md` | New audit file for this documentation pass. |
| `doc/IMPL-01-fix-mwm-registration.md` | Reviewed; MWM registration behavior did not change. |
| `doc/IMPL-02-mwm-metadata-storage.md` | Reviewed; MWM metadata storage did not change. |
| `doc/IMPL-03-mirror-service.md` | Reviewed; mirror service did not change. |
| `doc/IMPL-04-map-downloads-page.md` | Reviewed; downloads page did not change. |
| `doc/IMPL-05-place-page-drawer.md` | Reviewed; place-page drawer behavior did not change. |
| `doc/IMPLEMENTATION-ANDROID.md` | Reviewed; Android implementation did not change. |
| `doc/IMPLEMENTATION-CI-CD.md` | Applies; updated. |
| `doc/IMPLEMENTATION-IOS.md` | Applies; updated source layout and SwiftPM-compatible package tree. |
| `doc/IMPLEMENTATION-LINUX.md` | Reviewed; Linux implementation did not change. |
| `doc/IMPLEMENTATION-LOCALISATION.md` | Applies; updated active macOS source path. |
| `doc/IMPLEMENTATION-MACOS.md` | Applies; updated. |
| `doc/IMPLEMENTATION-MELOS-MONOREPO.md` | Reviewed; workspace membership did not change. |
| `doc/IMPLEMENTATION-NATIVE-MESSAGE-PASSING.md` | Applies; updated active Apple Pigeon/native bridge paths. |
| `doc/IMPLEMENTATION-NAVIGATION.md` | Applies; updated active Apple navigation bridge paths. |
| `doc/IMPLEMENTATION-SEARCH.md` | Applies; updated active Apple search bridge paths. |
| `doc/IMPLEMENTATION-SKIN-GENERATOR-DART.md` | Reviewed; skin generator did not change. |
| `doc/IMPLEMENTATION-WIN-IMPROVEMENT.md` | Reviewed; Windows improvement plan did not change. |
| `doc/IMPLEMENTATION-WIN-OVERLAY.md` | Reviewed; Windows overlay implementation did not change. |
| `doc/IMPLEMENTATION-WIN.md` | Reviewed; Windows implementation did not change. |
| `doc/INTERACTION-STATE-MACHINE.md` | Reviewed; interaction state did not change. |
| `doc/KEYMAP-ARCHITECTURE.md` | Applies; updated. |
| `doc/MAP-WIDGET-PARTS.md` | Reviewed; map widget parts did not change. |
| `doc/MONOREPO.md` | Reviewed; monorepo structure did not change. |
| `doc/PATCHING-GUIDE.md` | Reviewed; patching process did not change. CoMaps patch README was updated separately. |
| `doc/PLAN-SWIFT-PM.md` | Applies; updated. |
| `doc/PLAN-WASM.md` | Reviewed; WASM plan did not change. |
| `doc/RELEASE.md` | Reviewed; release process did not change beyond CI notes. |
| `doc/RENDER-LOOP.md` | Applies; updated active Apple render-loop source paths. |
| `doc/UI-LAYOUT.md` | Applies; updated. |
| `doc/WIDGETBOOK.md` | Reviewed; Widgetbook did not change. |
| `doc/issues/ISSUE-LOCALISATION.md` | Reviewed; localization issue did not change. |
| `doc/issues/ISSUE-arena-allocator-ffi.md` | Reviewed; allocator behavior did not change. |
| `doc/issues/ISSUE-data-extraction-cold-start.md` | Reviewed; data extraction behavior did not change. |
| `doc/issues/ISSUE-debug-logging-release.md` | Reviewed; logging policy did not change. |
| `doc/issues/ISSUE-dpi-mismatch-surface.md` | Reviewed; DPI/surface behavior did not change. |
| `doc/issues/ISSUE-egl-context-recreation.md` | Reviewed; EGL behavior did not change. |
| `doc/issues/ISSUE-event-stream-lifecycle.md` | Reviewed; event stream lifecycle did not change. |
| `doc/issues/ISSUE-ffi-string-allocation.md` | Reviewed; FFI string allocation did not change. |
| `doc/issues/ISSUE-indexed-stack-memory.md` | Reviewed; IndexedStack behavior did not change. |
| `doc/issues/ISSUE-jni-reflection-overhead.md` | Reviewed; JNI behavior did not change. |
| `doc/issues/ISSUE-linux-pixel-buffer-copy.md` | Reviewed; Linux pixel buffer behavior did not change. |
| `doc/issues/ISSUE-macos-platform-menu-lifecycle.md` | New issue record; applies. |
| `doc/issues/ISSUE-macos-resize-white-screen.md` | Applies; updated current macOS source paths. |
| `doc/issues/ISSUE-pigeon-async-overhead.md` | Reviewed; Pigeon async behavior did not change. |
| `doc/issues/ISSUE-placepage-deep-copy.md` | Applies; updated current iOS source path. |
| `doc/issues/ISSUE-swift-package-manager.md` | Applies; already updated for SwiftPM/runtime work. |
| `doc/issues/ISSUE-touch-event-throttling.md` | Reviewed; touch throttling did not change. |
| `doc/issues/ISSUE-windows-symbol-loading.md` | Reviewed; Windows symbol loading did not change. |
| `doc/layouts/PROGRESS.md` | Reviewed; layout implementation status did not require a progress-state change. |
| `doc/layouts/README.md` | Reviewed; top-level layout index did not change. |
| `doc/layouts/desktop/README.md` | Applies; updated. |
| `doc/layouts/mobile-landscape/README.md` | Reviewed; mobile-landscape layout did not change. |
| `doc/layouts/mobile-portrait/README.md` | Reviewed; mobile-portrait layout did not change. |
| `doc/layouts/tablet/README.md` | Reviewed; tablet layout did not change beyond the shared macOS menu shell documented elsewhere. |
| `doc/schemas/LAYERS.md` | Reviewed; layer schema did not change. |
| `doc/schemas/MANUAL-TESTING.md` | Applies; updated. |
| `doc/schemas/MIGRATION.md` | Reviewed; schema migration did not change. |
| `doc/schemas/PLAN-PROGRESS.md` | Applies; updated current Apple DuckDB bridge source paths. |
| `doc/schemas/README.md` | Reviewed; schema behavior did not change. |
| `doc/user-stories/README.md` | Reviewed; user-story index did not change. |
| `doc/user-stories/command-driven-drawing.md` | Reviewed; drawing commands did not change. |
| `doc/user-stories/design-components-widgetbook.md` | Reviewed; design components did not change. |
| `doc/user-stories/editable-keymaps.md` | Reviewed; keymap defaults were already captured there and central keymap docs were updated. |
| `doc/user-stories/layer-focus-centers.md` | Reviewed; layer focus behavior did not change. |
| `doc/user-stories/mwm-ordering-upgrades.md` | Reviewed; MWM ordering did not change. |
| `doc/user-stories/search-persistence.md` | Reviewed; search persistence did not change. |
| `doc/user-stories/shape-drawing-preview.md` | Applies; updated current Apple source paths. |
| `doc/user-stories/status-telemetry-copy.md` | Reviewed; status telemetry did not change. |
| `doc/user-stories/workbench-explorer-tree-grid.md` | Reviewed; Explorer tree/grid behavior did not change. |
| `doc/user-stories/workbench-modal-tools.md` | Applies; updated. |

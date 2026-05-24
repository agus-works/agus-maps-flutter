# macOS Platform Menu Lifecycle

## Status

Fixed in the example app.

The app now keeps a stable macOS platform menu across responsive layout
changes. The menu title is `Agus Suite`, `Cmd+Q` quits through the native
platform-provided Quit item, and desktop-only workbench tools appear only when
the rendered form factor is desktop.

## Findings

- The macOS runner starts with the default `MainMenu.xib` menus:
  `APP_NAME`, `Edit`, `View`, `Window`, and `Help`.
- Flutter's `PlatformMenuBar` does not append to those native menus. It
  replaces the full `NSApp.mainMenu` through the Flutter macOS menu plugin.
- The earlier desktop-only `PlatformMenuBar` supplied only a `Tools` menu. On
  macOS the first menu becomes the application menu, so `Point of Interest` and
  `Debug Console` appeared under the app name instead of under a separate
  Tools menu.
- The first fix restored `Agus Suite` and native app-menu items, but the
  `PlatformMenuBar` still lived only inside the desktop workbench branch. When
  the window resized to tablet or mobile layout, the widget was disposed and
  Flutter called `clearMenus()`, leaving the menu bar empty.
- Resizing back to desktop remounted the widget, which is why the menus could
  disappear and then later return.

## Plan

1. Move platform menu ownership above the responsive shell so it is not mounted
   and unmounted by desktop/tablet/mobile layout switches.
2. Recreate the macOS default menu structure in Dart because `PlatformMenuBar`
   replaces the native menu:
   - `Agus Suite`
   - `Edit`
   - `View`
   - `Window`
   - `Help`
3. Add `Tools` only for the desktop workbench layout.
4. Cache compact and desktop menu trees so the platform menu delegate receives a
   new menu tree only when the resolved layout crosses the compact/desktop
   boundary.
5. Keep this implementation macOS-only. Flutter's stock `flutter/menu` platform
   delegate is implemented for macOS; Windows and Linux do not have the same
   native menu delegate in Flutter's desktop shell.

## Steps Taken

- Added `_AgusPlatformMenuModel` in `example/lib/main.dart`.
- Cached two menu trees:
  - compact: `Agus Suite`, `Edit`, `View`, `Window`, `Help`
  - desktop: compact menus plus `Tools`
- Moved `PlatformMenuBar` to wrap the responsive shell for every macOS form
  factor.
- Removed the nested desktop-only `PlatformMenuBar` from `_buildDesktopWorkbench`.
- Kept `Point of Interest` and `Debug Console` sourced from the existing
  `_workbenchToolRegistry`.
- Set `CFBundleDisplayName` and `CFBundleName` to `Agus Suite` in
  `example/macos/Runner/Info.plist` while keeping the executable and output
  app bundle path as `agus_maps_flutter_example.app`.

## Expected Runtime Behavior

On macOS:

- Initial launch at compact/tablet width shows the default app menus:
  `Agus Suite`, `Edit`, `View`, `Window`, and `Help`.
- Resizing within compact/tablet/mobile widths does not clear or flicker the
  native menu.
- Resizing to desktop width adds `Tools`.
- Resizing back to compact removes only `Tools`; the default menus remain.
- `Cmd+Q` invokes the native platform Quit item.
- `Cmd+,` opens the app settings dialog.
- `Cmd+F` opens map search from the `Edit > Find` menu.

On Windows and Linux:

- No Flutter platform menu delegate is installed by this change.
- The responsive layout still works, and native app-window behavior is left to
  each runner/platform shell.

## Validation

Commands run from the repository root:

- `dart run melos exec --scope=agus_maps_flutter_example -- flutter analyze`
  - Passed.
- `dart run melos exec --scope=agus_maps_flutter_example -- flutter build macos --debug`
  - Passed.
  - Produced `example/build/macos/Build/Products/Debug/agus_maps_flutter_example.app`.
- `dart run melos exec --scope=agus_maps_flutter_example -- flutter build macos --release`
  - Passed.
  - Produced `example/build/macos/Build/Products/Release/agus_maps_flutter_example.app`.
- `cd example && perl -e 'alarm 25; exec @ARGV' build/macos/Build/Products/Debug/agus_maps_flutter_example.app/Contents/MacOS/agus_maps_flutter_example`
  - Reached `DrapeEngine created successfully`.
  - Reached `Texture registered`.
  - Reached `Map surface ready. Bundled maps are already registered.`
- `git diff --check`
  - Passed.

## Remaining Work

- Manual UI validation should still be performed in a real interactive macOS
  session by resizing the window across mobile, tablet, and desktop breakpoints
  and checking the menu bar after each transition.
- If Windows or Linux native menu support is introduced later, it should use a
  platform-specific delegate rather than assuming Flutter's macOS menu channel
  exists there.

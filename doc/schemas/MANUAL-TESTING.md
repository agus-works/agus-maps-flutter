# DuckDB Layer Manual Testing

This checklist covers the runtime behavior that is difficult to prove from build artifacts alone: DuckDB startup, native Android Drape rendering, drawing tools, layer controls, and backup behavior.

## When Manual Testing Is Needed

Manual testing is required when a change touches any of these areas:

- Android native map rendering or viewport refresh.
- `DuckDBLayerDrawController`, draw widgets, or map pointer handling.
- Layer visibility, z-order, metadata, or backup UI.
- DuckDB bridge startup, required extension loading, or migrations.
- Release packaging that changes which native libraries or assets are bundled.

Build and symbol checks are still useful, but they cannot confirm that drawn features appear on the moving native map surface or that touch gestures feel correct on a real device.

## Android Device Smoke

1. Connect a physical Android device or start an emulator.
2. Confirm Flutter can see it:

   ```bash
   flutter devices 2>&1 | tee ./output.log
   ```

3. Build and launch the example from the repo root. Replace `<device-id>` with the device id reported by Flutter:

   ```bash
   cd example && flutter run -d <device-id> --release 2>&1 | tee ../output.log
   ```

4. Open the About tab.
5. Confirm the DuckDB status card reports all of the following:
   - `DuckDB v1.5.2`
   - database open
   - required extensions loaded
   - spatial query ok

Expected result: the app remains responsive and the map can still be opened after the About-tab smoke succeeds.

## Drawing and Native Rendering

Start from the Map tab after the Android smoke has passed.

1. Tap the pin tool, tap the map once, enter a short title/note if desired, then commit.
2. Confirm a point appears on the map after commit.
3. Pan and zoom the map.
4. Confirm the point stays anchored to the same geographic location.
5. Tap the segment tool, tap two locations, then commit.
6. Confirm a line segment appears and remains anchored while panning/zooming.
7. Tap the line tool, add at least three vertices, undo the last vertex, add it again, then commit.
8. Confirm only the committed line appears; cancelled or undone vertices should not persist.
9. Tap the polygon tool, add at least three vertices, then commit.
10. Confirm the polygon outline appears. Filled polygons are not required for the current renderer.

Expected result: while a draw tool is active, map pan gestures should not accidentally move the map; after commit or cancel, normal map gestures should work again.

## Vertex Editing

1. Start a line or polygon sketch with at least three vertices.
2. Drag an existing vertex before committing.
3. Commit the feature.
4. Pan or zoom the map.

Expected result: the committed native feature follows the edited vertex positions, not the original positions.

## Layer Panel Controls

1. Open the layer panel.
2. Toggle the drawing layer off.
3. Confirm committed DuckDB features disappear after the renderer refreshes.
4. Toggle the layer on.
5. Confirm the features reappear.
6. Change the layer z-order if multiple DuckDB layers exist.
7. Confirm redraw still succeeds and the app does not throw an error.

Expected result: visibility and z-order changes persist through the `DuckDBLayerStore` and native refresh path.

## Backup Action

1. Open the layer panel.
2. Tap the backup action.
3. Confirm the UI reports a backup path or success state.
4. Restart the app.
5. Confirm previously committed features are still present.

Expected result: the backup action checkpoints the database and copies the `.duckdb` file without clearing current data.

## Android Release Artifact Check

Run this when validating release packaging locally:

```bash
cd example && flutter build apk --release --split-per-abi 2>&1 | tee ../output.log
cd example && flutter build appbundle --release 2>&1 | tee ../output.log
```

Expected result: Flutter produces split APKs for `armeabi-v7a`, `arm64-v8a`, and `x86_64`, plus a release AAB. Prefer the split APK matching the test device ABI for manual install checks.

## Desktop Notes

The Android native DuckDB renderer and `screenPointToLatLon()` projection are Android-only for now. Desktop manual testing should focus on build/package validation and the About-tab DuckDB smoke once private desktop DuckDB runtime artifacts are available.

For macOS example smoke:

```bash
cd example && flutter build macos --debug 2>&1 | tee ../output.log
```

Expected result: the app builds and the About tab can report DuckDB health when the macOS DuckDB framework is bundled.

## macOS Platform Menu Resize Smoke

Run this after changes to responsive shell layout, app menus, or macOS runner
metadata:

```bash
cd example && flutter run -d macos --debug 2>&1 | tee ../output.log
```

1. Launch the app at the default window size.
2. Confirm the menu bar shows `Agus Suite`, `Edit`, `View`, `Window`, and
   `Help`.
3. Resize wide enough for the desktop workbench.
4. Confirm `Tools` appears while the default menus remain.
5. Resize back to tablet/mobile width.
6. Confirm only `Tools` disappears and the default menus remain clickable.
7. Press `Cmd+Q`.

Expected result: the app quits normally without Force Quit, and no resize
transition clears the native menu bar.

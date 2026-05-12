# User Story: Shape Drawing and Editing Edge Preview

## As a map editor
I want the segment, line, or polygon that I am creating or editing to show its
edges immediately, so that I can clearly understand the shape before I commit
or finish the edit.

## Background
Map authoring is error-prone when placed vertices are visible but the connecting
edges are intermittent. Users need immediate visual confirmation that every new
point belongs to the intended segment, line, or polygon. Editing must also
update the same feature rather than creating duplicate features.

The intermittent macOS failure had three contributing causes:

- The macOS and iOS native DuckDB interaction renderer paths were behind the
  shared C++ implementation. They did not diff created, updated, and removed
  user-line marks consistently, so Drape could keep stale edit geometry or miss
  line updates while the sketch changed.
- Interaction WKT was parsed as one flat point list on the platform copies,
  which made multi-geometry edit previews unreliable.
- The Flutter map wrapper only forwarded pointer moves for captured edit-handle
  drags. During new drawing, uncaptured mouse moves and hover events did not
  reach the draw controller or native projection path, so live preview edges
  could not update consistently between placed vertices.
- The temporary native point-stamp fallback proved the geometry was reaching
  Drape, but it produced dotted/thick-looking edges. Interaction edges must use
  a true native line mark so the visible preview is a simple thin continuous
  stroke.
- A follow-up retest showed the styled line request reached native code
  (`lineWidth=... opacity=... dashed=...`), but the mark was assigned to
  `OverlayLayer`. CoMaps renders user line marks in the `UserLineLayer` pass, so
  interaction and committed feature lines must stay on `UserLineLayer`.
- A later retest showed `lineMarks=... depth=UserLineLayer` but still no visible
  line. The remaining mismatch with CoMaps' working `Track` renderer was line
  parameters: DuckDB lines now return unscaled base widths and a single-layer
  depth of `0`, matching `Track::GetWidth` and `Track::GetDepth`.
- When `UserLineMark` submissions still did not appear despite matching track
  parameters, DuckDB line edges moved to CoMaps' direct native `DrapeApiLineData`
  path. That path draws native line buckets with depth testing disabled at the
  end of the frame, and is now the authoritative renderer for committed DuckDB
  line/polygon/segment features and active draw/edit interaction edges.

The supported behavior now uses native Drape interaction geometry only. The map
wrapper passively forwards map pointer movement to a Pigeon host API, each
platform updates its native map-pointer tracker, and native code projects the
latest physical pixel position through the current viewport before Dart updates
the active sketch or edit geometry. Native renderers submit styleable
`DrapeApiLineData` geometry for interaction edges through a Pigeon-configured
line style, so segment/line/polygon edges remain visibly traceable as thin
native strokes without a Flutter overlay, point-stamp fallback, or `UserLineMark`
fallback.

## Acceptance Criteria

### Drawing Preview
- ✅ After each segment, line, or polygon vertex is added, the visible
  interaction geometry connects it to the previous placed vertex when enough
  vertices exist for an edge.
- ✅ While a line or polygon drawing remains open for more vertices, moving the
  pointer shows a preview edge from the last placed vertex to the pointer.
- ✅ Segment drawing stops extending preview geometry after the second vertex,
  because the segment is complete.
- ✅ Polygon drawing renders as a closed shape by connecting the final preview or
  placed vertex back to the first vertex.
- ✅ New drawing previews render as thin blue dashed native lines; active edits
  and selected feature/layer highlights render as thin solid amber native lines.
- ✅ Existing visible non-active line, segment, and polygon edges render through
  the same native Drape API path as thin muted slate lines.
- ✅ Color, opacity, thickness, and dashed/solid behavior are configurable from
  Flutter through Pigeon.

### Feature Editing
- ✅ Existing point, segment, line, and polygon features expose visible edit
  handles and shape edges while they are being edited.
- ✅ Moving a feature vertex updates the visible edit geometry immediately.
- ✅ Committing an edit updates the original feature id instead of inserting a
  new duplicate feature.
- ✅ Pointer-up auto-save during a drag also updates the same feature id and
  keeps the edit session active.

## Implementation References
- Drawing controller: `lib/src/layers/duckdb_draw_controller.dart`
- Native map pointer host API: `pigeons/agus_maps_api.dart`
- Native interaction renderer API:
  `updateDrapeInteractionGeometry`
- Native macOS renderer:
  `macos/Classes/agus_maps_flutter_macos.mm`
- Native iOS renderer:
  `ios/Classes/agus_maps_flutter_ios.mm`
- Native Android/shared renderer:
  `src/agus_maps_flutter.cpp`
- Native Linux/Windows interaction line renderers:
  `src/agus_maps_flutter_linux.cpp`,
  `src/agus_maps_flutter_win.cpp`
- Example app edit wiring: `example/lib/main.dart`
- Layer manager edit entry point:
  `example/lib/features/map/widgets/adaptive_layer_manager.dart`

## Debug Logging
- Dart interaction markers:
  - `[AgusDemo] DuckDB map tap ...`
  - `[AgusDemo] DuckDB pointer move ...`
  - `[AgusDemo] DuckDB interaction render submit ...`
  - `[DuckDBDraw] renderNative mode=drawing ...`
  - `[DuckDBDraw] commit insert ...` and `[DuckDBDraw] commit update ...`
- Native interaction marker:
   - `[AgusMapsFlutter] DuckDB interaction geometry: mode=... geometries=... points=... lines=... lineMarks=... drapeApiLines=... renderer=DrapeApiLineData depthTest=0 ... lineWidth=... opacity=... dashed=...`
   - `[AgusMapsFlutter] DuckDB committed render geometry: features=... pointMarks=... lineMarks=... drapeApiLines=... renderer=DrapeApiLineData baseWidth=2.00 depthTest=0 style=existing-visible`

## Testing Approach
- Unit tests: `test/duckdb_draw_controller_test.dart`
- Coverage:
   - Segment, line, and polygon preview WKT emitted after vertex and pointer
     updates
   - Controller display vertices include the native-projected live preview point
   - Segment max-vertex preview boundary
   - Polygon closure behavior
    - Edit commit and pointer-up edit persistence preserve the existing feature id
   - Polygon edit commits preserve closed WKT while updating the original feature
     id
   - Default native interaction line style stays thin, blue, dashed, and within
      valid opacity/width bounds
   - Active edit/selection interaction line style stays thin, solid, amber, and
      within valid opacity/width bounds
- Manual macOS verification:
   - Rebuild or run the macOS debug target after native `.mm`, map wrapper, or
     Pigeon host API changes.
   - Draw a segment, line, and polygon and confirm each new vertex produces a
     Dart `render submit` log and a native `DuckDB interaction geometry` log with
     `lines=1` once at least two points are present.

## Related Features
- Command-driven drawing and interaction state safety
- Layer/feature focus centers and active selection
- Workbench Explorer tree-grid selection

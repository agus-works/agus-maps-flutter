# Workbench modal tools and pane registry

## Story

As a desktop user, I want Settings, About, and bottom-panel tools to open from
global workbench state instead of being tied to a particular pane, so I can close
or move panes and still recover the same focused content from the Activity Bar or
command bar.

## Registered modal surfaces

| Surface | Entry points | Behavior |
| --- | --- | --- |
| Settings | Activity Bar bottom item, `Open Settings` command | Opens as a locking focused modal. The left column lists settings categories; the right column hosts the visual settings editor with fuzzy search across ids, titles, descriptions, options, and tags. |
| About Agus Maps | Activity Bar bottom item, `Open About` command | Opens as a locking focused modal with the existing version, license, attribution, DuckDB, and third-party component content. |

## Registered bottom-panel tools

| Tool | Command bar id | Behavior |
| --- | --- | --- |
| Point of Interest | `tools-point-of-interest` and Tools > Point of Interest | Shows and focuses the bottom Panel, then selects the point-of-interest tab without resetting its content. |
| Debug Console | `tools-debug-console` and Tools > Debug Console | Shows and focuses the bottom Panel, then selects the debug console tab without clearing accumulated output. |

## Notes

- The command bar and platform Tools menu expose the same bottom-panel tools.
  The example app registry is `_workbenchToolRegistry` in `example/lib/main.dart`;
  future tools should be added there rather than as one-off pane buttons.
- Map Presentation is part of Explorer because it controls native map-layer
  visibility alongside Project Layers and MWM Maps.

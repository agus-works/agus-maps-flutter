# User Stories

This directory contains user stories documenting implemented features in Agus Maps Flutter. Each story describes the user's perspective, acceptance criteria, implementation references, and testing approach.

## Purpose

User stories serve as:
- **Feature documentation**: What the feature does and why it exists
- **Implementation verification**: Acceptance criteria match actual behavior
- **Testing guides**: Manual and automated testing approaches
- **Onboarding**: New contributors understand feature scope and design decisions

## Story Format

Each user story follows this structure:

1. **As a [user role]**: Who benefits from this feature
2. **I want [capability]**: What the user wants to accomplish
3. **So that [benefit]**: Why this capability matters
4. **Background**: Context and problem statement
5. **Acceptance Criteria**: Concrete, testable requirements (✅ marks implemented)
6. **Implementation References**: Files, APIs, schemas, components
7. **Testing Approach**: Unit, integration, manual testing strategies
8. **Documentation**: Links to detailed docs
9. **Related Features**: Cross-references to connected stories

## Available Stories

### Core Features
- **[Search Persistence and Result Preservation](search-persistence.md)**: DuckDB cache, instant results, map data revision tracking, cache invalidation
- **[Command-Driven Drawing and Interaction State Safety](command-driven-drawing.md)**: State machine, command enablement guards, workflow protection
- **[Layer/Feature Focus Centers and Active Selection](layer-focus-centers.md)**: Center point persistence, async calculation, focus workflow, Layer Manager integration

### UI Features
- **[Status Telemetry Copy with Notifications](status-telemetry-copy.md)**: Live map telemetry, copy-to-clipboard, VS Code-style notifications
- **[Editable and Platform-Aware Keymaps](editable-keymaps.md)**: Platform defaults, user overrides, conflict detection, JSON import/export

### Map Management
- **[MWM Ordering, Upgrades, and Active Map Management](mwm-ordering-upgrades.md)**: Version management, download/update workflow, ordering preferences, visibility controls

### Design System
- **[Reusable Agus Design Components and Widgetbook Coverage](design-components-widgetbook.md)**: Component library, theme system, interactive catalog, testing infrastructure

## Story Status

All stories in this directory document **implemented and validated** features. They are not proposals or future plans. Aspirational features belong in separate planning docs (e.g., `doc/PLAN-*.md`).

## Writing New Stories

When adding a new user story:

1. **Verify implementation first**: Only document features that are complete and tested
2. **Use concrete criteria**: Acceptance criteria must be observable and testable
3. **Mark with ✅**: Clearly indicate implemented requirements
4. **Reference actual code**: Link to real files, APIs, tables, not hypothetical ones
5. **Include testing approach**: Document how to verify the feature works
6. **Cross-reference**: Link to related stories and detailed documentation

## Relationship to Other Docs

- **User stories** (this directory): High-level feature documentation from user perspective
- **Implementation docs** (`doc/IMPLEMENTATION-*.md`): Technical details, APIs, workflows
- **Architecture docs** (`doc/ARCHITECTURE-*.md`, `doc/KEYMAP-ARCHITECTURE.md`, etc.): System design, patterns, contracts
- **Schema docs** (`doc/schemas/`): Database schemas, JSON schemas, data models
- **How-to guides** (`doc/WIDGETBOOK.md`, `doc/MANUAL-TESTING.md`): Step-by-step instructions

## Maintenance

User stories should be updated when:
- Feature behavior changes significantly
- New acceptance criteria are implemented
- Implementation references change (file moves, API renames)
- Testing approaches evolve
- Related features are added or removed

Stories should **not** include:
- Aspirational or planned features (use planning docs instead)
- Unchecked acceptance criteria (all criteria must be ✅ implemented)
- References to non-existent files or APIs
- Outdated information contradicting actual implementation

## Quick Reference

| Feature | Story | Implementation Doc | Schema/API |
|---------|-------|-------------------|------------|
| Search cache | [search-persistence.md](search-persistence.md) | `IMPLEMENTATION-SEARCH.md` | `agus.search_result_cache` |
| Drawing state machine | [command-driven-drawing.md](command-driven-drawing.md) | `INTERACTION-STATE-MACHINE.md` | `AppInteractionStateController` |
| Focus centers | [layer-focus-centers.md](layer-focus-centers.md) | `schemas/LAYERS.md` | `focus_center_lon/lat` columns |
| Status telemetry | [status-telemetry-copy.md](status-telemetry-copy.md) | `IMPLEMENTATION_STATUS_TELEMETRY.md` | `MapTelemetry` model |
| Keymaps | [editable-keymaps.md](editable-keymaps.md) | `KEYMAP-ARCHITECTURE.md` | `agus.keymap_settings` |
| MWM management | [mwm-ordering-upgrades.md](mwm-ordering-upgrades.md) | `COMMAND-BAR.md`, `schemas/LAYERS.md` | `MwmStorage` API |
| Design system | [design-components-widgetbook.md](design-components-widgetbook.md) | `WIDGETBOOK.md` | `packages/agus_design` |

## Contributing

When contributing new features:
1. Implement and test the feature
2. Update or create user story in this directory
3. Update related implementation/architecture docs
4. Verify all cross-references are accurate
5. Run validation: `dart run melos run analyze` and `dart run melos run test`

import 'package:flutter/material.dart';

/// A compact property-grid row inspired by Visual Studio and Blender panels.
class CompactPropertyRow {
  /// Creates a property-grid row.
  const CompactPropertyRow({
    required this.name,
    required this.value,
    this.trailing,
  });

  /// Property label.
  final String name;

  /// Property value.
  final Widget value;

  /// Optional trailing action.
  final Widget? trailing;
}

/// Compact text value for property-grid and data-grid cells.
class CompactPropertyText extends StatelessWidget {
  /// Creates a compact single or two-line property value.
  const CompactPropertyText(
    this.text, {
    super.key,
    this.maxLines = 1,
    this.fontWeight,
  });

  /// Text to display.
  final String text;

  /// Maximum rendered lines before ellipsizing.
  final int maxLines;

  /// Optional font weight override.
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            height: 1.25,
            fontWeight: fontWeight,
          ),
    );
  }
}

/// A dense boolean value control for compact property grids.
class CompactBooleanToggle extends StatelessWidget {
  /// Creates a compact boolean control.
  const CompactBooleanToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Current boolean value.
  final bool value;

  /// Called when the value changes.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        value ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final background =
        value ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow;

    return Semantics(
      button: true,
      toggled: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(!value),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value ? Icons.check_circle : Icons.circle_outlined,
                  size: 12,
                  color: foreground,
                ),
                const SizedBox(width: 4),
                Text(
                  value ? 'On' : 'Off',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width, dense property grid for desktop inspector surfaces.
class CompactPropertyGrid extends StatelessWidget {
  /// Creates a compact property grid.
  const CompactPropertyGrid({
    super.key,
    required this.rows,
    this.nameWidth = 112,
    this.rowHeight = 22,
    this.padding = EdgeInsets.zero,
  });

  /// Rows displayed by the grid.
  final List<CompactPropertyRow> rows;

  /// Fixed label-column width.
  final double nameWidth;

  /// Minimum row height.
  final double rowHeight;

  /// Grid outer padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (rows.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          'No attributes available.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < rows.length; index++)
              _CompactPropertyGridRow(
                row: rows[index],
                nameWidth: nameWidth,
                rowHeight: rowHeight,
                shaded: index.isEven,
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactPropertyGridRow extends StatelessWidget {
  const _CompactPropertyGridRow({
    required this.row,
    required this.nameWidth,
    required this.rowHeight,
    required this.shaded,
  });

  final CompactPropertyRow row;
  final double nameWidth;
  final double rowHeight;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            shaded ? colorScheme.surfaceContainerLowest : colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: IntrinsicHeight(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: rowHeight),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: nameWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    border: Border(
                      right: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.25),
                      child: row.value,
                    ),
                  ),
                ),
              ),
              if (row.trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Align(
                    alignment: Alignment.center,
                    child: row.trailing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Column metadata for [CompactDataGrid].
class CompactDataColumn {
  /// Creates a data-grid column.
  const CompactDataColumn({
    required this.label,
    this.flex = 1,
    this.width,
  });

  /// Header label.
  final String label;

  /// Flex used when [width] is null.
  final int flex;

  /// Optional fixed width.
  final double? width;
}

/// A dense, full-width data grid for desktop panes.
class CompactDataGrid extends StatelessWidget {
  /// Creates a compact data grid.
  const CompactDataGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.rowHeight = 30,
    this.headerHeight = 28,
  });

  /// Grid columns.
  final List<CompactDataColumn> columns;

  /// Row cells. Each row should match [columns] length.
  final List<List<Widget>> rows;

  /// Body row height.
  final double rowHeight;

  /// Header row height.
  final double headerHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompactDataGridRow(
            columns: columns,
            cells: [
              for (final column in columns)
                _GridText(column.label, fontWeight: FontWeight.w700),
            ],
            height: headerHeight,
            backgroundColor: colorScheme.surfaceContainerLow,
          ),
          for (var index = 0; index < rows.length; index++)
            _CompactDataGridRow(
              columns: columns,
              cells: rows[index],
              height: rowHeight,
              backgroundColor: index.isEven
                  ? colorScheme.surfaceContainerLowest
                  : colorScheme.surface,
            ),
        ],
      ),
    );
  }
}

class _CompactDataGridRow extends StatelessWidget {
  const _CompactDataGridRow({
    required this.columns,
    required this.cells,
    required this.height,
    required this.backgroundColor,
  });

  final List<CompactDataColumn> columns;
  final List<Widget> cells;
  final double height;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < columns.length; index++)
              _GridCell(
                column: columns[index],
                showDivider: index < columns.length - 1,
                child: index < cells.length ? cells[index] : const SizedBox(),
              ),
          ],
        ),
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.column,
    required this.child,
    required this.showDivider,
  });

  final CompactDataColumn column;
  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(right: BorderSide(color: colorScheme.outlineVariant))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
    final width = column.width;
    if (width != null) return SizedBox(width: width, child: content);
    return Expanded(flex: column.flex, child: content);
  }
}

class _GridText extends StatelessWidget {
  const _GridText(this.text, {this.fontWeight});

  final String text;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: fontWeight,
          ),
    );
  }
}

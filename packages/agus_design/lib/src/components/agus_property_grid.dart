import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

/// A single row in an [AgusPropertyGrid].
@immutable
class AgusPropertyRow {
  /// Creates a property row.
  const AgusPropertyRow({
    required this.name,
    required this.value,
    this.trailing,
  });

  /// Property label.
  final String name;

  /// Property value widget.
  final Widget value;

  /// Optional trailing action.
  final Widget? trailing;
}

/// Compact text value for property grids.
class AgusPropertyText extends StatelessWidget {
  /// Creates a compact text value.
  const AgusPropertyText(
    this.text, {
    this.maxLines = 1,
    this.fontWeight,
    super.key,
  });

  /// Text to display.
  final String text;

  /// Maximum rendered lines before ellipsizing.
  final int maxLines;

  /// Optional font weight.
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colors.editorForeground,
        height: 1.25,
        fontWeight: fontWeight,
      ),
    );
  }
}

/// A dense property grid for inspectors and details panels.
class AgusPropertyGrid extends StatelessWidget {
  /// Creates a property grid.
  const AgusPropertyGrid({
    required this.rows,
    this.nameWidth = 112,
    this.rowHeight = 22,
    this.padding = EdgeInsets.zero,
    this.emptyLabel = 'No attributes available.',
    super.key,
  }) : assert(nameWidth >= 0),
       assert(rowHeight >= 0);

  /// Rows displayed by the grid.
  final List<AgusPropertyRow> rows;

  /// Fixed label-column width.
  final double nameWidth;

  /// Minimum row height.
  final double rowHeight;

  /// Grid outer padding.
  final EdgeInsets padding;

  /// Text shown when [rows] is empty.
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    if (rows.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          emptyLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.editorForeground.withValues(alpha: 0.72),
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.editorGroupBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < rows.length; index++)
              _AgusPropertyGridRow(
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

class _AgusPropertyGridRow extends StatelessWidget {
  const _AgusPropertyGridRow({
    required this.row,
    required this.nameWidth,
    required this.rowHeight,
    required this.shaded,
  });

  final AgusPropertyRow row;
  final double nameWidth;
  final double rowHeight;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: shaded
            ? colors.editorBackground
            : colors.panelBackground.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: colors.editorGroupBorder)),
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
                    color: colors.sideBarBackground,
                    border: Border(
                      right: BorderSide(color: colors.editorGroupBorder),
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.editorForeground.withValues(
                            alpha: 0.72,
                          ),
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
                    child: row.value,
                  ),
                ),
              ),
              if (row.trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Center(child: row.trailing),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

class AgusSidebar extends StatelessWidget {
  const AgusSidebar({
    required this.title,
    required this.sections,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final List<Widget> sections;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Material(
      color: colors.sideBarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 35,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.sideBarTitleForeground,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: sections),
          ),
        ],
      ),
    );
  }
}

class AgusViewSection extends StatefulWidget {
  const AgusViewSection({
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.initiallyExpanded = true,
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool initiallyExpanded;

  @override
  State<AgusViewSection> createState() => _AgusViewSectionState();
}

class _AgusViewSectionState extends State<AgusViewSection> {
  late bool expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: colors.sideBarBackground,
          child: InkWell(
            hoverColor: colors.hoverBackground,
            onTap: () => setState(() => expanded = !expanded),
            child: SizedBox(
              height: 22,
              child: Row(
                children: [
                  const SizedBox(width: 2),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: colors.sideBarForeground,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.sideBarForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ...widget.actions,
                ],
              ),
            ),
          ),
        ),
        if (expanded) widget.child,
      ],
    );
  }
}

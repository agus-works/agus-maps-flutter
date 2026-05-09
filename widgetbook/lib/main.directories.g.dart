// dart format width=80
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering

// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AppGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:agus_design_widgetbook/use_cases/components/navigation_use_cases.dart'
    as _agus_design_widgetbook_use_cases_components_navigation_use_cases;
import 'package:agus_design_widgetbook/use_cases/components/surfaces_use_cases.dart'
    as _agus_design_widgetbook_use_cases_components_surfaces_use_cases;
import 'package:agus_design_widgetbook/use_cases/layout/layout_use_cases.dart'
    as _agus_design_widgetbook_use_cases_layout_layout_use_cases;
import 'package:agus_design_widgetbook/use_cases/settings/settings_use_cases.dart'
    as _agus_design_widgetbook_use_cases_settings_settings_use_cases;
import 'package:widgetbook/widgetbook.dart' as _widgetbook;

final directories = <_widgetbook.WidgetbookNode>[
  _widgetbook.WidgetbookCategory(
    name: 'Components',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'navigation',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AgusActivityBar',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Interactive',
                builder:
                    _agus_design_widgetbook_use_cases_components_navigation_use_cases
                        .buildAgusActivityBarUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusActivityBarButton',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Button states',
                builder:
                    _agus_design_widgetbook_use_cases_components_navigation_use_cases
                        .buildAgusActivityBarButtonUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusEditorTabBar',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Workspace tabs',
                builder:
                    _agus_design_widgetbook_use_cases_components_navigation_use_cases
                        .buildAgusEditorTabBarUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusEditorTabButton',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Tab states',
                builder:
                    _agus_design_widgetbook_use_cases_components_navigation_use_cases
                        .buildAgusEditorTabButtonUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusStatusBar',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Status indicators',
                builder:
                    _agus_design_widgetbook_use_cases_components_navigation_use_cases
                        .buildAgusStatusBarUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusStatusBarItemView',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Item states',
                builder:
                    _agus_design_widgetbook_use_cases_components_navigation_use_cases
                        .buildAgusStatusBarItemViewUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusTreeView',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Explorer tree',
                builder:
                    _agus_design_widgetbook_use_cases_components_navigation_use_cases
                        .buildAgusTreeViewUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'surfaces',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AgusCommandBar',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Command bar',
                builder:
                    _agus_design_widgetbook_use_cases_components_surfaces_use_cases
                        .buildAgusCommandBarUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusCommandCenter',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Command center',
                builder:
                    _agus_design_widgetbook_use_cases_components_surfaces_use_cases
                        .buildAgusCommandCenterUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusCommandDialog',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Command dialog',
                builder:
                    _agus_design_widgetbook_use_cases_components_surfaces_use_cases
                        .buildAgusCommandDialogUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusEditorHost',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Editor host',
                builder:
                    _agus_design_widgetbook_use_cases_components_surfaces_use_cases
                        .buildAgusEditorHostUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusSidebar',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Explorer sidebar',
                builder:
                    _agus_design_widgetbook_use_cases_components_surfaces_use_cases
                        .buildAgusSidebarUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusTitleBar',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Window title bar',
                builder:
                    _agus_design_widgetbook_use_cases_components_surfaces_use_cases
                        .buildAgusTitleBarUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusViewSection',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Collapsible section',
                builder:
                    _agus_design_widgetbook_use_cases_components_surfaces_use_cases
                        .buildAgusViewSectionUseCase,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  _widgetbook.WidgetbookCategory(
    name: 'Layouts',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'workspace',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AgusSplitView',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Resizable panes',
                builder:
                    _agus_design_widgetbook_use_cases_layout_layout_use_cases
                        .buildAgusSplitViewUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusWorkbench',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Full workbench',
                builder:
                    _agus_design_widgetbook_use_cases_layout_layout_use_cases
                        .buildAgusWorkbenchUseCase,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  _widgetbook.WidgetbookCategory(
    name: 'Settings',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'editor',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AgusSettingControl',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Field variants',
                builder:
                    _agus_design_widgetbook_use_cases_settings_settings_use_cases
                        .buildAgusSettingControlUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusSettingRow',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Setting row',
                builder:
                    _agus_design_widgetbook_use_cases_settings_settings_use_cases
                        .buildAgusSettingRowUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusSettingScopeSelector',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Scope selector',
                builder:
                    _agus_design_widgetbook_use_cases_settings_settings_use_cases
                        .buildAgusSettingScopeSelectorUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AgusSettingsEditor',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Responsive settings editor',
                builder:
                    _agus_design_widgetbook_use_cases_settings_settings_use_cases
                        .buildAgusSettingsEditorUseCase,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];

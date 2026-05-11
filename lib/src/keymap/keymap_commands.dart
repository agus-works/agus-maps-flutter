part of '../../agus_maps_flutter.dart';

/// Command identifiers for application actions.
///
/// These command IDs are referenced by keymap definitions and action handlers.
class AgusCommandId {
  const AgusCommandId._();

  // Map Navigation
  static const String panUp = 'map.pan.up';
  static const String panDown = 'map.pan.down';
  static const String panLeft = 'map.pan.left';
  static const String panRight = 'map.pan.right';
  static const String zoomIn = 'map.zoom.in';
  static const String zoomOut = 'map.zoom.out';
  static const String resetRotation = 'map.reset.rotation';
  static const String toggleFullscreen = 'map.toggle.fullscreen';

  // Search & Command Bar
  static const String openCommandBar = 'commandbar.open';
  static const String openSearch = 'search.open';
  static const String focusSearch = 'search.focus';

  // Layer Management
  static const String toggleLayerPanel = 'layer.toggle.panel';
  static const String newDrawingLayer = 'layer.new.drawing';
  static const String toggleCurrentLayer = 'layer.toggle.current';

  // Selection & Editing
  static const String selectAll = 'edit.select.all';
  static const String deselectAll = 'edit.deselect.all';
  static const String delete = 'edit.delete';
  static const String undo = 'edit.undo';
  static const String redo = 'edit.redo';
  static const String copy = 'edit.copy';
  static const String cut = 'edit.cut';
  static const String paste = 'edit.paste';
  static const String duplicate = 'edit.duplicate';

  // Tool Selection
  static const String selectTool = 'tool.select';
  static const String panTool = 'tool.pan';
  static const String drawPointTool = 'tool.draw.point';
  static const String drawLineTool = 'tool.draw.line';
  static const String drawPolygonTool = 'tool.draw.polygon';

  // Application
  static const String showAbout = 'app.show.about';
  static const String showSettings = 'app.show.settings';
  static const String quit = 'app.quit';
  static const String refresh = 'app.refresh';

  /// Returns a human-readable display name for a command.
  static String displayName(String commandId) {
    switch (commandId) {
      case panUp:
        return 'Pan Up';
      case panDown:
        return 'Pan Down';
      case panLeft:
        return 'Pan Left';
      case panRight:
        return 'Pan Right';
      case zoomIn:
        return 'Zoom In';
      case zoomOut:
        return 'Zoom Out';
      case resetRotation:
        return 'Reset Rotation';
      case toggleFullscreen:
        return 'Toggle Fullscreen';
      case openCommandBar:
        return 'Open Command Bar';
      case openSearch:
        return 'Open Search';
      case focusSearch:
        return 'Focus Search';
      case toggleLayerPanel:
        return 'Toggle Layer Panel';
      case newDrawingLayer:
        return 'New Drawing Layer';
      case toggleCurrentLayer:
        return 'Toggle Current Layer';
      case selectAll:
        return 'Select All';
      case deselectAll:
        return 'Deselect All';
      case delete:
        return 'Delete';
      case undo:
        return 'Undo';
      case redo:
        return 'Redo';
      case copy:
        return 'Copy';
      case cut:
        return 'Cut';
      case paste:
        return 'Paste';
      case duplicate:
        return 'Duplicate';
      case selectTool:
        return 'Select Tool';
      case panTool:
        return 'Pan Tool';
      case drawPointTool:
        return 'Draw Point';
      case drawLineTool:
        return 'Draw Line';
      case drawPolygonTool:
        return 'Draw Polygon';
      case showAbout:
        return 'Show About';
      case showSettings:
        return 'Show Settings';
      case quit:
        return 'Quit';
      case refresh:
        return 'Refresh';
      default:
        return commandId;
    }
  }

  /// Returns a description for a command.
  static String description(String commandId) {
    switch (commandId) {
      case panUp:
        return 'Pan the map upward';
      case panDown:
        return 'Pan the map downward';
      case panLeft:
        return 'Pan the map to the left';
      case panRight:
        return 'Pan the map to the right';
      case zoomIn:
        return 'Zoom in on the map';
      case zoomOut:
        return 'Zoom out on the map';
      case resetRotation:
        return 'Reset map rotation to north-up';
      case toggleFullscreen:
        return 'Toggle fullscreen mode';
      case openCommandBar:
        return 'Open the command bar';
      case openSearch:
        return 'Open search dialog';
      case focusSearch:
        return 'Focus the search field';
      case toggleLayerPanel:
        return 'Toggle the layer management panel';
      case newDrawingLayer:
        return 'Create a new drawing layer';
      case toggleCurrentLayer:
        return 'Toggle visibility of current layer';
      case selectAll:
        return 'Select all features';
      case deselectAll:
        return 'Deselect all features';
      case delete:
        return 'Delete selected features';
      case undo:
        return 'Undo last action';
      case redo:
        return 'Redo last undone action';
      case copy:
        return 'Copy selected features';
      case cut:
        return 'Cut selected features';
      case paste:
        return 'Paste features';
      case duplicate:
        return 'Duplicate selected features';
      case selectTool:
        return 'Activate selection tool';
      case panTool:
        return 'Activate pan tool';
      case drawPointTool:
        return 'Activate point drawing tool';
      case drawLineTool:
        return 'Activate line drawing tool';
      case drawPolygonTool:
        return 'Activate polygon drawing tool';
      case showAbout:
        return 'Show about dialog';
      case showSettings:
        return 'Show settings dialog';
      case quit:
        return 'Quit the application';
      case refresh:
        return 'Refresh the current view';
      default:
        return '';
    }
  }
}

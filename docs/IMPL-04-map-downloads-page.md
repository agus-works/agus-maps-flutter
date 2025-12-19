# IMPL-04: Map Downloads Page

## Overview

A Flutter page/widget for browsing and downloading MWM map files, with mirror selection, disk space enforcement, and download progress tracking.

## UI Structure

```
┌─────────────────────────────────────────────┐
│  Map Downloads                          ✕   │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ Mirror: [WFR Software ▼] 45ms ●        │ │
│ │ Snapshot: [250608 (Jun 8, 2025) ▼]     │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│  Downloaded (3)              Available (45) │
│  ──────────                                 │
│ ┌─────────────────────────────────────────┐ │
│ │ ● World.mwm              98MB  bundled  │ │
│ │ ● WorldCoasts.mwm        23MB  bundled  │ │
│ │ ● Gibraltar.mwm          1.2MB 250608   │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│  Available Regions                          │
│  ─────────────────                          │
│ ┌─────────────────────────────────────────┐ │
│ │ ○ Afghanistan            45MB   [↓]     │ │
│ │ ○ Albania                12MB   [↓]     │ │
│ │ ○ Algeria                89MB   [↓]     │ │
│ │ ● Gibraltar              1.2MB  ✓       │ │
│ │ ○ Spain                  1.5GB  [↓]     │ │
│ │ ...                                     │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Disk: 12.5GB free | After: 11.0GB      │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

## Disk Space Rules

1. **Block download** if `availableSpace - fileSize < 128MB`
   - Show error: "Insufficient disk space. Need at least 128MB remaining after download."

2. **Warn** if `availableSpace - fileSize < 1024MB`
   - Show warning: "After download, only X MB will remain. Consider freeing up space."

3. **Display** remaining space after download in UI

## Implementation

### File: `example/lib/downloads_page.dart`

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:agus_maps_flutter/mirror_service.dart';
import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus;
import 'package:http/http.dart' as http;

class MapDownloadsPage extends StatefulWidget {
  final MwmStorage mwmStorage;
  
  const MapDownloadsPage({super.key, required this.mwmStorage});
  
  @override
  State<MapDownloadsPage> createState() => _MapDownloadsPageState();
}

class _MapDownloadsPageState extends State<MapDownloadsPage> {
  final MirrorService _mirrorService = MirrorService();
  
  Mirror? _selectedMirror;
  Snapshot? _selectedSnapshot;
  List<Snapshot> _snapshots = [];
  List<MwmRegion> _regions = [];
  
  bool _isLoading = false;
  String? _error;
  
  // Download tracking
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadErrors = {};
  
  // Disk space
  int _availableSpace = 0;
  
  @override
  void initState() {
    super.initState();
    _init();
  }
  
  Future<void> _init() async {
    setState(() => _isLoading = true);
    
    try {
      // Measure mirror latencies
      await _mirrorService.measureLatencies();
      
      // Select fastest available mirror
      final available = _mirrorService.mirrors.where((m) => m.isAvailable).toList();
      if (available.isEmpty) {
        throw Exception('No mirrors available');
      }
      
      _selectedMirror = available.reduce(
        (a, b) => (a.latencyMs ?? 999999) < (b.latencyMs ?? 999999) ? a : b
      );
      
      // Load snapshots
      _snapshots = await _mirrorService.getSnapshots(_selectedMirror!);
      if (_snapshots.isNotEmpty) {
        _selectedSnapshot = _snapshots.first;
        await _loadRegions();
      }
      
      // Get disk space
      await _updateDiskSpace();
      
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _loadRegions() async {
    if (_selectedMirror == null || _selectedSnapshot == null) return;
    
    setState(() => _isLoading = true);
    try {
      _regions = await _mirrorService.getRegions(_selectedMirror!, _selectedSnapshot!);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _updateDiskSpace() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      // Get available space using platform channel or package
      // For now, use a placeholder - implement with disk_space package
      _availableSpace = 10 * 1024 * 1024 * 1024; // 10GB placeholder
    }
    setState(() {});
  }
  
  Future<void> _downloadRegion(MwmRegion region) async {
    if (_selectedMirror == null || _selectedSnapshot == null) return;
    
    final url = _mirrorService.getDownloadUrl(
      _selectedMirror!, _selectedSnapshot!, region
    );
    
    // Get file size
    int fileSize = region.sizeBytes ?? await _mirrorService.getFileSize(url) ?? 0;
    
    // Check disk space
    final remainingAfter = _availableSpace - fileSize;
    
    if (remainingAfter < 128 * 1024 * 1024) {
      // Block: less than 128MB remaining
      _showError('Insufficient disk space. Need at least 128MB remaining after download.');
      return;
    }
    
    if (remainingAfter < 1024 * 1024 * 1024) {
      // Warn: less than 1GB remaining
      final remainingMb = remainingAfter ~/ (1024 * 1024);
      final proceed = await _showWarning(
        'After download, only $remainingMb MB will remain. Continue?'
      );
      if (!proceed) return;
    }
    
    // Start download
    setState(() {
      _downloadProgress[region.name] = 0.0;
      _downloadErrors.remove(region.name);
    });
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/${region.fileName}';
      final file = File(filePath);
      
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      
      final contentLength = response.contentLength ?? fileSize;
      int received = 0;
      
      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        
        setState(() {
          _downloadProgress[region.name] = received / contentLength;
        });
      }
      
      await sink.close();
      
      // Save metadata
      await widget.mwmStorage.upsert(MwmMetadata(
        regionName: region.name,
        snapshotVersion: _selectedSnapshot!.version,
        fileSize: received,
        downloadDate: DateTime.now(),
        filePath: filePath,
        isBundled: false,
      ));
      
      // Register with map engine
      agus.registerSingleMap(filePath);
      
      // Update disk space
      _availableSpace -= received;
      
      setState(() {
        _downloadProgress.remove(region.name);
      });
      
    } catch (e) {
      setState(() {
        _downloadProgress.remove(region.name);
        _downloadErrors[region.name] = e.toString();
      });
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
  
  Future<bool> _showWarning(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Low Disk Space'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ?? false;
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map Downloads')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildContent(),
    );
  }
  
  Widget _buildContent() {
    return Column(
      children: [
        // Mirror and Snapshot selection
        _buildSelectors(),
        
        // Disk space indicator
        _buildDiskSpace(),
        
        // Downloaded and Available lists
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: 'Downloaded (${widget.mwmStorage.getAll().length})'),
                    Tab(text: 'Available (${_regions.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildDownloadedList(),
                      _buildAvailableList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSelectors() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Mirror dropdown
          Row(
            children: [
              const Text('Mirror: '),
              Expanded(
                child: DropdownButton<Mirror>(
                  value: _selectedMirror,
                  isExpanded: true,
                  items: _mirrorService.mirrors.map((m) {
                    final latency = m.latencyMs != null ? '${m.latencyMs}ms' : 'N/A';
                    final status = m.isAvailable ? '●' : '○';
                    return DropdownMenuItem(
                      value: m,
                      child: Text('${m.name} $latency $status'),
                    );
                  }).toList(),
                  onChanged: (m) {
                    setState(() => _selectedMirror = m);
                    _loadRegions();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Snapshot dropdown
          Row(
            children: [
              const Text('Snapshot: '),
              Expanded(
                child: DropdownButton<Snapshot>(
                  value: _selectedSnapshot,
                  isExpanded: true,
                  items: _snapshots.map((s) {
                    final date = '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}';
                    return DropdownMenuItem(
                      value: s,
                      child: Text('${s.version} ($date)'),
                    );
                  }).toList(),
                  onChanged: (s) {
                    setState(() => _selectedSnapshot = s);
                    _loadRegions();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildDiskSpace() {
    final availableGb = _availableSpace / (1024 * 1024 * 1024);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[200],
      child: Row(
        children: [
          const Icon(Icons.storage, size: 16),
          const SizedBox(width: 8),
          Text('Disk: ${availableGb.toStringAsFixed(1)} GB free'),
        ],
      ),
    );
  }
  
  Widget _buildDownloadedList() {
    final downloaded = widget.mwmStorage.getAll();
    return ListView.builder(
      itemCount: downloaded.length,
      itemBuilder: (ctx, i) {
        final meta = downloaded[i];
        final sizeMb = meta.fileSize / (1024 * 1024);
        return ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(meta.regionName),
          subtitle: Text('${sizeMb.toStringAsFixed(1)} MB'),
          trailing: Text(
            meta.isBundled ? 'bundled' : meta.snapshotVersion,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        );
      },
    );
  }
  
  Widget _buildAvailableList() {
    return ListView.builder(
      itemCount: _regions.length,
      itemBuilder: (ctx, i) {
        final region = _regions[i];
        final isDownloaded = widget.mwmStorage.isDownloaded(region.name);
        final progress = _downloadProgress[region.name];
        final error = _downloadErrors[region.name];
        
        final sizeMb = region.sizeBytes != null
            ? (region.sizeBytes! / (1024 * 1024)).toStringAsFixed(1)
            : '?';
        
        return ListTile(
          leading: Icon(
            isDownloaded ? Icons.check_circle : Icons.circle_outlined,
            color: isDownloaded ? Colors.green : Colors.grey,
          ),
          title: Text(region.name),
          subtitle: error != null
              ? Text(error, style: const TextStyle(color: Colors.red))
              : Text('$sizeMb MB'),
          trailing: progress != null
              ? SizedBox(
                  width: 48,
                  child: CircularProgressIndicator(value: progress),
                )
              : isDownloaded
                  ? const Icon(Icons.check)
                  : IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: () => _downloadRegion(region),
                    ),
        );
      },
    );
  }
  
  @override
  void dispose() {
    _mirrorService.dispose();
    super.dispose();
  }
}
```

## Dependencies

Add to `example/pubspec.yaml`:
```yaml
dependencies:
  path_provider: ^2.1.0
  http: ^1.1.0
```

## Integration with Main App

```dart
// In main.dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => MapDownloadsPage(mwmStorage: _mwmStorage),
  ),
);
```

## Disk Space Implementation Note

For accurate disk space checking on Android/iOS, use a platform channel or the `disk_space` package:

```yaml
dependencies:
  disk_space: ^0.2.1
```

```dart
import 'package:disk_space/disk_space.dart';

final free = await DiskSpace.getFreeDiskSpace; // in MB
_availableSpace = (free ?? 0) * 1024 * 1024; // convert to bytes
```

## Notes

- Download happens in foreground - consider adding background download support later
- No resume support for interrupted downloads - consider adding Range header support
- Deleting maps would require removing from storage and optionally from disk
- Update icon could be shown when `mwmStorage.hasUpdate(region, latestSnapshot)` returns true

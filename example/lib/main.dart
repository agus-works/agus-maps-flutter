import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Initializing...';
  String _mapPath = '';
  String _debug = '';

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    try {
      _log('Starting initialization...');
      
      // 1. Extract map file
      _log('Extracting map...');
      String mapPath = await agus_maps_flutter.extractMap('assets/maps/Gibraltar.mwm');
      _log('Map path: $mapPath');
      
      // 2. Extract CoMaps data files (classificator.txt, types.txt, etc.)
      _log('Extracting data files...');
      String dataPath = await agus_maps_flutter.extractDataFiles();
      _log('Data path: $dataPath');
      
      String storagePath = File(mapPath).parent.path;
      _log('Storage path: $storagePath');
      
      // 3. Initialize with extracted data files
      _log('Calling initWithPaths()...');
      agus_maps_flutter.initWithPaths(dataPath, storagePath);
      _log('initWithPaths() complete');
      
      _log('Calling loadMap()...');
      agus_maps_flutter.loadMap(mapPath);
      _log('loadMap() complete');
      
      _log('Calling setView()...');
      agus_maps_flutter.setView(36.1408, -5.3536, 14);
      _log('setView() complete');
      
      if (!mounted) return;
      setState(() {
        _status = 'Success';
        _mapPath = mapPath;
      });
    } catch (e, stackTrace) {
      _log('ERROR: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _status = 'Error: $e';
      });
    }
  }
  
  void _log(String msg) {
    debugPrint('[AgusDemo] $msg');
    if (mounted) {
      setState(() {
        _debug += '$msg\n';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Agus Maps (CoMaps)'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Status: $_status\nMap: $_mapPath'),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(_debug, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                ),
              ),
            ),
            // Debug controls
            Container(
              height: 50,
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => agus_maps_flutter.setView(36.1407, -5.3535, 12),
                    child: const Text('Gibraltar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

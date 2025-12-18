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
  bool _mapReady = false;
  int? _textureId;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    try {
      _log('Starting initialization...');
      
      // 1. Extract map files
      _log('Extracting World.mwm...');
      await agus_maps_flutter.extractMap('assets/maps/World.mwm');
      _log('Extracting WorldCoasts.mwm...');
      await agus_maps_flutter.extractMap('assets/maps/WorldCoasts.mwm');
      _log('Extracting Gibraltar.mwm...');
      String mapPath = await agus_maps_flutter.extractMap('assets/maps/Gibraltar.mwm');
      _log('Map path: $mapPath');
      
      // 2. Extract ICU data for transliteration
      _log('Extracting icudt75l.dat...');
      await agus_maps_flutter.extractMap('assets/maps/icudt75l.dat');
      
      // 3. Extract CoMaps data files (classificator.txt, types.txt, etc.)
      // These files are extracted directly to the files directory
      _log('Extracting data files...');
      String dataPath = await agus_maps_flutter.extractDataFiles();
      _log('Data path: $dataPath');
      
      // storagePath is the same as dataPath since data files are extracted to files directory
      String storagePath = dataPath;
      _log('Storage path: $storagePath');
      
      // 4. Initialize with extracted data files
      // Both resource and writable paths point to the same directory
      // so that scope "w" and "r" both find the files
      _log('Calling initWithPaths()...');
      agus_maps_flutter.initWithPaths(storagePath, storagePath);
      _log('initWithPaths() complete');
      
      _log('Calling loadMap()...');
      agus_maps_flutter.loadMap(mapPath);
      _log('loadMap() complete');
      
      _log('Calling setView()...');
      agus_maps_flutter.setView(36.1408, -5.3536, 14);
      _log('setView() complete');
      
      // 5. Create the rendering surface
      _log('Creating map surface...');
      final textureId = await agus_maps_flutter.createMapSurface();
      _log('Map surface created, textureId: $textureId');

      if (!mounted) return;
      setState(() {
        _status = 'Success';
        _mapPath = mapPath;
        _mapReady = true;
        _textureId = textureId;
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
            // Map rendering area
            Expanded(
              child: _mapReady && _textureId != null
                  ? Texture(textureId: _textureId!)
                  : SingleChildScrollView(
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

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
  bool _dataReady = false;
  bool _mapReady = false;
  final agus_maps_flutter.AgusMapController _mapController = agus_maps_flutter.AgusMapController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
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
      _log('Extracting data files...');
      String dataPath = await agus_maps_flutter.extractDataFiles();
      _log('Data path: $dataPath');
      
      // 4. Initialize with extracted data files
      _log('Calling initWithPaths()...');
      agus_maps_flutter.initWithPaths(dataPath, dataPath);
      _log('initWithPaths() complete');
      
      _log('Calling loadMap()...');
      agus_maps_flutter.loadMap(mapPath);
      _log('loadMap() complete');

      if (!mounted) return;
      setState(() {
        _status = 'Data ready - creating map...';
        _mapPath = mapPath;
        _dataReady = true;
      });
    } catch (e, stackTrace) {
      _log('ERROR: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _status = 'Error: $e';
      });
    }
  }
  
  void _onMapReady() {
    _log('Map surface ready!');
    setState(() {
      _status = 'Map ready! Try panning/zooming.';
      _mapReady = true;
    });
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
              child: _dataReady
                  ? agus_maps_flutter.AgusMap(
                      initialLat: 36.1408,
                      initialLon: -5.3536,
                      initialZoom: 14,
                      onMapReady: _onMapReady,
                      controller: _mapController,
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_debug, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                      ),
                    ),
            ),
            // Control buttons
            Container(
              height: 60,
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => _mapController.moveToLocation(36.1407, -5.3535, 14),
                    child: const Text('Gibraltar'),
                  ),
                  TextButton(
                    onPressed: () => _mapController.moveToLocation(0, 0, 2),
                    child: const Text('World'),
                  ),
                  TextButton(
                    onPressed: () => _mapController.moveToLocation(40.4168, -3.7038, 12),
                    child: const Text('Madrid'),
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

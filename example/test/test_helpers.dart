import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpExampleWidget(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1200, 800),
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AgusThemeData.dark().toThemeData(),
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

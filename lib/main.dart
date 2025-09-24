import 'package:flutter/material.dart';
import 'package:fitness_ui_kit/pages/bluetooth_devices_page.dart';
import 'router.dart' as router;

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BluetoothDevicesPage(),
      onGenerateRoute: router.generateRoute,
    );
  }
}

void main() {
  runApp(const MyApp());
}

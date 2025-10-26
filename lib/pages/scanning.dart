import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils.dart';

// This page is used to scan the QR code label on the back of your respeck
class ScanningPage extends StatefulWidget {
  const ScanningPage({Key? key}) : super(key: key);

  @override
  State<ScanningPage> createState() => _ScanningPageState();
}

class _ScanningPageState extends State<ScanningPage> {
  String? qr_code;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR code'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: WillPopScope(onWillPop: () async {
          Navigator.pop(context, qr_code);
          return false;
        }, child: MobileScanner(
          onDetect: (result) {
            if (result.barcodes.isNotEmpty) {
              final value = result.barcodes.first.rawValue;
              if (qr_code != value) {
                showToast(value ?? '');
                qr_code = value;
              }
            }
          },
        )));
  }
}

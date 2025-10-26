import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart' as myService;
import 'respeck_setting_page.dart';

class BluetoothDevicesPage extends StatefulWidget {
  const BluetoothDevicesPage({Key? key}) : super(key: key);

  @override
  State<BluetoothDevicesPage> createState() => _BluetoothDevicesPageState();
}

class _BluetoothDevicesPageState extends State<BluetoothDevicesPage> {
  final myService.BluetoothService _bluetoothService = myService.BluetoothService();
  bool _isConnecting = false;
  bool _isConnected = false;
  String _statusText = "Not connected with Respeck.";

  void _connectRespeck() async {
    setState(() {
      _isConnecting = true;
      _statusText = "Scanning and connecting...";
    });
    await _bluetoothService.scanAndConnectRespeck(
      onData: ({
        required double x,
        required double y,
        required double z,
        int? batteryLevel,
        bool? isCharging,
        int? respeckVersion,
        String? prediction,
        int? bufferSize,
      }) {
        if (!_isConnected) {
          setState(() {
            _isConnected = true;
            _isConnecting = false;
            _statusText = "Connected to Respeck";
          });
          Navigator.pushNamedAndRemoveUntil(context, "/root_app", (route) => false);
        }
      },
      onStatus: (msg) {
        setState(() {
          _statusText = msg;
        });
      },
    );
    if (!_isConnected) {
      setState(() {
        _isConnecting = false;
        _statusText = "Failed to connect to Respeck.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _statusText,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _isConnected ? Colors.green : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Make sure the Respeck device is powered on. Click the button below to connect.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (_isConnecting || _isConnected) ? null : _connectRespeck,
                  child: _isConnecting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    'Connect',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RespeckSettingPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('设置 Respeck UUID'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil('/root_app', (route) => false);
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('跳过到首页'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
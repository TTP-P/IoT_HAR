import 'package:flutter/material.dart';
import '../globals.dart';
import 'scanning.dart';

class RespeckSettingPage extends StatefulWidget {
  const RespeckSettingPage({Key? key}) : super(key: key);

  @override
  State<RespeckSettingPage> createState() => _RespeckSettingPageState();
}

class _RespeckSettingPageState extends State<RespeckSettingPage> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: respeckUUID);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveUUID() {
    setState(() {
      respeckUUID = _controller.text.trim();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Respeck UUID saved!')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Respeck UUID')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Respeck UUID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveUUID,
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ScanningPage()),
                      );
                      if (result != null && result is String) {
                        setState(() {
                          _controller.text = result;
                        });
                      }
                    },
                    child: const Text('Scan QR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

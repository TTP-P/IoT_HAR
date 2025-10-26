
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fb;
import '../globals.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected
}




// 工具函数：将两个字节合成为加速度值（g）
double combineAccelBytes(int upper, int lower) {
  int lower2 = lower & 0xFF;
  int value = (upper << 8) | lower2;
  return (value) / 16384.0;
}
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  fb.BluetoothDevice? _respeckDevice;
  int respeckVersion = 0;

  /// 扫描并连接 Respeck 设备，解析数据流
  Future<void> scanAndConnectRespeck({
    required void Function({
      required double x,
      required double y,
      required double z,
      int? batteryLevel,
      bool? isCharging,
      int? respeckVersion,
      String? prediction,
      int? bufferSize,
    }) onData,
    required void Function(String msg) onStatus,
  }) async {
    _respeckDevice = null;
    respeckVersion = 0;
    onStatus("Searching for Respeck $respeckUUID...");

    final scanSub = fb.FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (_respeckDevice == null && r.device.remoteId.str == respeckUUID) {
          if (r.advertisementData.advName == "Res6AL") {
            _respeckDevice = r.device;
            respeckVersion = 6;
            fwString = "6AL";
          } else if (r.advertisementData.advName == "ResV5i") {
            _respeckDevice = r.device;
            respeckVersion = 5;
            fwString = "5i";
          } else {
            onStatus("Respeck firmware is too old");
          }
        }
      }
    }, onError: (e) => onStatus("Scan error: $e"));

    fb.FlutterBluePlus.cancelWhenScanComplete(scanSub);

    await fb.FlutterBluePlus.adapterState
        .where((val) => val == fb.BluetoothAdapterState.on)
        .first;

    await fb.FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await fb.FlutterBluePlus.isScanning.where((val) => val == false).first;

    if (_respeckDevice == null) {
      onStatus("No Respeck found.");
      return;
    }

    // 连接设备
    await _respeckDevice!.connect();
    onStatus("Connected to \\${_respeckDevice.toString()}");

    // 监听断开
    final disconnectSub = _respeckDevice!.connectionState.listen((state) {
      if (state == fb.BluetoothConnectionState.disconnected) {
        onStatus("Respeck disconnected");
      }
    });
    _respeckDevice!.cancelWhenDisconnected(disconnectSub, delayed: true, next: true);

    // 发现服务
    final services = await _respeckDevice!.discoverServices();
    fb.BluetoothService? ser;
    fb.BluetoothCharacteristic? cha;
    for (final s in services) {
      if (s.serviceUuid.str == "00001523-1212-efde-1523-785feabcd125") {
        ser = s;
        break;
      }
    }
    if (ser != null) {
      for (final c in ser.characteristics) {
        if (c.characteristicUuid.str == "00001524-1212-efde-1523-785feabcd125") {
          cha = c;
          break;
        }
      }
    }
    if (cha == null) {
      onStatus("Respeck accel characteristic not found");
      return;
    }

    // 订阅数据
    final dataSub = cha.onValueReceived.listen((value) async {
      final ul = Uint8List.fromList(value);
      final bd = ul.buffer.asByteData();
      int ts = bd.getUint32(0);
      ts = (ts * 197 * 1000 / 32768).toInt();
      int packetSeqNumber = bd.getUint16(4);

      int? battLevel;
      bool charging = false;
      if (respeckVersion == 6) {
        battLevel = bd.getUint8(6);
        charging = bd.getUint8(7) == 1;
      }

      int seqNumInPacket = 0;
      double x = 0, y = 0, z = 0;
      for (int i = 8; i < bd.lengthInBytes; i += 6) {
        int b1 = bd.getInt8(i);
        int b2 = bd.getInt8(i + 1);
        x = combineAccelBytes(b1, b2);
        int b3 = bd.getInt8(i + 2);
        int b4 = bd.getInt8(i + 3);
        y = combineAccelBytes(b3, b4);
        int b5 = bd.getInt8(i + 4);
        int b6 = bd.getInt8(i + 5);
        z = combineAccelBytes(b5, b6);

        // HARService.addSample(x, y, z); // 你可以在外部调用
        seqNumInPacket++;
      }

      String? prediction;
      // if (HARService.hasEnoughSamples()) {
      //   prediction = HARService.predict();
      // }

      onData(
        x: x,
        y: y,
        z: z,
        batteryLevel: battLevel,
        isCharging: charging,
        respeckVersion: respeckVersion,
        prediction: prediction,
        bufferSize: null,
      );
    });
    _respeckDevice!.cancelWhenDisconnected(dataSub);

    await Future.delayed(const Duration(seconds: 3));
    await cha.setNotifyValue(true);
  }

  void dispose() {
    _respeckDevice?.disconnect();
  }
}

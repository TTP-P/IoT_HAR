import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'utils.dart';
import 'home.dart';
import 'globals.dart';
import 'har_service.dart';

// This file contains the BLE code to scan for and connect to a respeck sensor.
// Once connected, we notify the acceleration characteristic and decode the
// stream of packets to obtain x,y,z acceleration in g and battery level.
// Each sample is written to a CSV file and the UI is updated with the latest
// values.

Future<void> scanForRespeck(MyHomePageState ui) async {
  // listen to scan results
  // Note: `onScanResults` clears the results between scans. You should use
  //  `scanResults` if you want the current scan results *or* the results from the previous scan.
  BluetoothDevice? respeck;
  int respeckVersion = 0;

  showToast("Searching for Respeck $respeckUUID...");

  var subscription = FlutterBluePlus.onScanResults.listen(
    (results) {
      if (results.isNotEmpty) {
        for (ScanResult r in results) {
          //ScanResult r = results.last; // the most recently found device
          //print('${r.device.remoteId}: "${r.advertisementData.advName}" found!');
          if (respeck == null && r.device.remoteId.str == respeckUUID) {
            if (r.advertisementData.advName == "Res6AL") {
              respeck = r.device;
              respeckVersion = 6;
              fwString = "6AL";
            } else if (r.advertisementData.advName == "ResV5i") {
              respeck = r.device;
              respeckVersion = 5;
              fwString = "5i";
            } else {
              showToast("Respeck firmware is too old");
            }
          }
        }
      }
    },
    onError: (e) => print(e),
  );

  // cleanup: cancel subscription when scanning stops
  FlutterBluePlus.cancelWhenScanComplete(subscription);

  // Wait for Bluetooth enabled & permission granted
  // In your real app you should use `FlutterBluePlus.adapterState.listen` to handle all states
  await FlutterBluePlus.adapterState
      .where((val) => val == BluetoothAdapterState.on)
      .first;

  // Start scanning w/ timeout
  // Optional: use `stopScan()` as an alternative to timeout
  await FlutterBluePlus.startScan(
      //withServices: [Guid("180D")], // match any of the specified services
      //withNames: ["Bluno"], // *or* any of the specified names
      timeout: const Duration(seconds: 5));

  // wait for scanning to stop
  await FlutterBluePlus.isScanning.where((val) => val == false).first;
  print("end of scanning");

  // listen for disconnection
  var subscription2 =
      respeck!.connectionState.listen((BluetoothConnectionState state) async {
    if (state == BluetoothConnectionState.disconnected) {
      // 1. typically, start a periodic timer that tries to
      //    reconnect, or just call connect() again right now
      // 2. you must always re-discover services after disconnection!
      print(
          "${respeck?.disconnectReason?.code} ${respeck?.disconnectReason?.description}");
    }
  });

  // cleanup: cancel subscription when disconnected
  //   - [delayed] This option is only meant for `connectionState` subscriptions.
  //     When `true`, we cancel after a small delay. This ensures the `connectionState`
  //     listener receives the `disconnected` event.
  //   - [next] if true, the the stream will be canceled only on the *next* disconnection,
  //     not the current disconnection. This is useful if you setup your subscriptions
  //     before you connect.
  respeck!.cancelWhenDisconnected(subscription2, delayed: true, next: true);

  if (respeck == null) {
    return;
  }

  // Now connect to the respeck
  await respeck!.connect();
  print("CONNECTED to Respeck!");
  showToast("Connected to ${respeck.toString()}");

  BluetoothService? ser;
  BluetoothCharacteristic? cha;

  // Service discovery
  // Note: You must call discoverServices after every re-connection!
  List<BluetoothService> services = await respeck!.discoverServices();
  //services.forEach((service) {
  for (BluetoothService s in services) {
    if (s.serviceUuid.str == "00001523-1212-efde-1523-785feabcd125") {
      ser = s;
      break;
    }
  }

  // Read all characteristics provided by this service and choose the
  // acceleration characteristic
  if (ser != null) {
    var characteristics = ser.characteristics;
    for (BluetoothCharacteristic c in characteristics) {
      if (c.characteristicUuid.str == "00001524-1212-efde-1523-785feabcd125") {
        print("found accel characteristic");
        cha = c;
        break;
      }
    }
  }

  // Subscribe to acceleration values
  if (cha != null) {
    final subscription3 = cha.onValueReceived.listen((value) async {
      ui.received_packet = true;
      // onValueReceived is updated:
      //   - anytime read() is called
      //   - anytime a notification arrives (if subscribed)

      //print("RECEIVED packet:");
      //print(value);

      // Decode packet:
      //https://stackoverflow.com/questions/59627795/parse-int-and-float-values-from-uint8list-dart
      //https://stackoverflow.com/questions/72418830/how-to-target-specific-int-bits-in-an-int-array-into-uint16-or-32

      // Timestamp when this packet was received, according to the phone clock
      DateTime packet_received_ts = DateTime.now();

      Uint8List ul = Uint8List.fromList(value);
      ByteData bd = ul.buffer.asByteData();

      int ts = bd.getUint32(0);
      ts = (ts * 197 * 1000 / 32768)
          .toInt(); // timestamp from the respeck clock, in ms
      print(ts);

      // Sequence number can be used to detect dropped packets
      int packetSeqNumber = bd.getUint16(4);
      print(packetSeqNumber);

      // Battery status (respeck version 6 only)
      int? battLevel;
      bool charging = false;

      if (respeckVersion == 6) {
        battLevel = bd.getUint8(6);
        if (bd.getUint8(7) == 1) {
          charging = true;
        }
      }

      // NOTE: The respeck sends multiple samples per packet, for efficiency
      // For each sample in this packet, append a line to the CSV file,
      String csv_str = "";
      int seqNumInPacket = 0;
      double x = 0, y = 0, z = 0;

      bool predictionReady = false;

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

        // Add sample to HAR service buffer for real-time activity recognition
        // HARService.addSample(x, y, z);
        // Modified 
        final featureResult = ui.featureEngineer.processSample(x, y, z);

        final featureMap = featureResult.toFeatureMap();
        final ready = HARService.addFeatureSample(featureMap, isStepBoundary: featureResult.isStepBoundary); if (ready) { predictionReady = true; }


        // final featureResult = ui.featureEngineer.processSample(x, y, z);

        csv_str +=
            "${packet_received_ts.millisecondsSinceEpoch},$ts,$packetSeqNumber,$seqNumInPacket,$x,$y,$z,${featureResult.gravityX},${featureResult.gravityY},${featureResult.gravityZ},${featureResult.linAccX},${featureResult.linAccY},${featureResult.linAccZ},${featureResult.accelMag},${featureResult.linAccMag},${featureResult.jerkMag},${featureResult.accelVert},${featureResult.accelHorizMag},${featureResult.strideVariability},${featureResult.movementConsistency},${featureResult.jerkRms}\n";

        seqNumInPacket++;
        ui.recorded_samples++;
      }

      // Perform HAR prediction if we have enough samples
      String? prediction;
      if (predictionReady) { prediction = HARService.getLatestPrediction(); }


      // Update the UI to show the latest data (called once per packet)
      ui.updateUI(
        x: x,
        y: y, 
        z: z,
        batteryLevel: battLevel,
        isCharging: charging,
        respeckVersion: respeckVersion,
        prediction: prediction,
        bufferSize: HARService.getBufferSize()
      );

      // update elapsed time counter if recording
      if (ui.recording) {
        int elapsed_secs =
            packet_received_ts.difference(ui.start_timestamp!).inSeconds;

        ui.recording_info =
            "Written ${ui.recorded_samples} samples (${elapsed_secs} seconds)";

            // write to the CSV file
            await csvFile.writeAsString(csv_str, mode: FileMode.append, flush: false);
      }

    });

    // cleanup: cancel subscription when disconnected
    respeck!.cancelWhenDisconnected(subscription3);

    await Future.delayed(const Duration(seconds: 3));

    // subscribe
    // Note: If a characteristic supports both **notifications** and **indications**,
    // it will default to **notifications**. This matches how CoreBluetooth works on iOS.
    await cha.setNotifyValue(true);
  }
}

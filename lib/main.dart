import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'globals.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'home.dart';

// This file starts the app and displays the home screen.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read app version information
  PackageInfo.fromPlatform().then((PackageInfo packageInfo) {
    appVersionName = packageInfo.version; // App version
    appVersionCode = int.parse(packageInfo.buildNumber); // Build number
  });

  // Read pairing information form shared preferences
  respeckUUID = await asyncPrefs.getString('rid');
  print("respeckUUID:${respeckUUID}");

  subjectID = await asyncPrefs.getString('sid');
  print("subjectID:${subjectID}");

  // get storage folder - must be accessible to the user for PDIoT
  storageFolder = await getDownloadsDirectory();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pdiot',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: "PDIoT"),
    );
  }
}

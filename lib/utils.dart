import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';

String sentenceToCamelCase(String sentence) {
  List<String> words = sentence.split(' ');
  String camelCase = words[0].toLowerCase(); // Keep the first word in lowercase

  for (int i = 1; i < words.length; i++) {
    camelCase +=
        words[i][0].toUpperCase() + words[i].substring(1).toLowerCase();
  }

  return camelCase;
}

void showToast(String s) {
  Fluttertoast.showToast(
      msg: s,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.SNACKBAR,
      timeInSecForIosWeb: 1,
      backgroundColor: Colors.blueGrey,
      textColor: Colors.white,
      fontSize: 16.0);
}

// The respeck sends acceleration values as two bytes, which need to be combined
// into a signed integer, and then scaled to report the acceleration in g
double combineAccelBytes(int upper, int lower) {
  int lower2 = lower & 0xFF;
  int value = (upper << 8) | lower2;
  return (value) / 16384.0;
}

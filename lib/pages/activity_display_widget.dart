import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';


class ActivityDisplayWidget extends StatelessWidget {
  final String activity;
  final bool isConnected;
  const ActivityDisplayWidget({Key? key, required this.activity, required this.isConnected}) : super(key: key);



  static const Map<String, String> _activityGifMapping = {
    "Cycling": "assets/gifs/cycling.gif",
    "WalkDownstairs": "assets/gifs/stairsDown.gif",
    "Jogging": "assets/gifs/jogging.gif",
    "Lying": "assets/gifs/lying.gif",
    "Sitting": "assets/gifs/sitting.gif",
    "WalkUpstairs": "assets/gifs/stairsUp.gif",
    "Walking": "assets/gifs/walking.gif",
    "Unknown Activity": "assets/gifs/unknown.gif",
    "No device connected": "assets/gifs/signal.gif",
    "Loading...": "assets/gifs/813.gif",
    "Error": "assets/gifs/Error.gif",
  };

  @override
  Widget build(BuildContext context) {
    final gifPath = _activityGifMapping[activity] ?? _activityGifMapping["Unknown Activity"]!;
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green : Colors.red,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "CURRENT ACTIVITY",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  activity,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Image.asset(gifPath, fit: BoxFit.cover),
          ),
        ],
      ),
    );
  }
}

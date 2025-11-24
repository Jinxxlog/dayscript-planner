import 'package:flutter/material.dart';

void main() {
  runApp(const SettingsWindow());
}

class SettingsWindow extends StatelessWidget {
  const SettingsWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Settings",
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Settings"),
        ),
        body: const Center(
          child: Text("Settings Window"),
        ),
      ),
    );
  }
}
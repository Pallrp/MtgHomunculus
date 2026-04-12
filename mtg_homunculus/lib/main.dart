import 'package:flutter/material.dart';
import 'screens/game_tracker_screen.dart';

void main() {
  runApp(const MtgHomunculusApp());
}

class MtgHomunculusApp extends StatelessWidget {
  const MtgHomunculusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MtgHomunculus',
      debugShowCheckedModeBanner: false,
      // ThemeData.dark() gives us a sensible dark baseline to build on top of
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.blueGrey.shade700,
        ),
      ),
      home: const GameTrackerScreen(),
    );
  }
}

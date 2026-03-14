import 'package:flutter/material.dart';
import 'package:note_vision/features/musicxml_inspector/music_inspector_screen.dart';
import '../../../features/collection/presentation/collection_screen.dart';
// import '../../collection/presentation/collection_screen.dart';
// import '../../../collection_page.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Note Vision',
              style: TextStyle(
                fontFamily: 'MaturaMTScriptCapitals',
                fontSize: 48,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            Image.asset(
              'assets/images/logo.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('getStartedButton'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CollectionScreen(),
                  ),
                );
              },
              child: const Text(
                'Get Started',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              key: const Key('TestButton'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MusicXmlInspectorScreen(),
                  ),
                );
              },
              child: const Text(
                "Dev's Workbench",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
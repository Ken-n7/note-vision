import 'package:flutter/material.dart';
import 'CollectionPage.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Main(),
    ),
  );
}

class Main extends StatelessWidget {
  const Main({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App name using custom font
            const Text(
              'Note Vision',
              style: TextStyle(
                fontFamily: 'MaturaMTScriptCapitals',
                fontSize: 48,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            // Logo placeholder - user should replace with actual asset
            Image.asset(
              'assets/images/logo.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 24),
            // Get started button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                // Navigate to HomePage when button is pressed
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CollectionPage()),
                );
              },
              child: const Text(
                'Get Started',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
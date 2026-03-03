import 'package:flutter/material.dart';
import 'package:note_vision/widgets/drawer.dart';   // ← adjust path
import 'HomePage.dart';   // adjust path if needed

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  int _currentIndex = 0;

  BottomNavigationBarItem _buildBottomNavItem(IconData icon, String label) {
    return BottomNavigationBarItem(
      icon: Icon(icon),
      label: label,
    );
  }

  void _handleBottomNavigation(int index, BuildContext context) {
    if (index == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
    // Add handling for other tabs later if needed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // Now using the extracted widget
      endDrawer: const CollectionDrawer(),

      appBar: AppBar(
        key: const ValueKey('collectionAppBar'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('My Files', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),

      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              const Text(
                'No Image Found!!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                key: const ValueKey('addImageButton'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HomePage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(24),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Colors.black12),
                  elevation: 4,
                ),
                child: const Icon(Icons.add, size: 32, color: Colors.black),
              ),
              const SizedBox(height: 8),
              const Text('Add Image'),
            ],
          ),
        ),
      ),

      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          key: const ValueKey('mainBottomNav'),
          backgroundColor: Colors.black,
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
            _handleBottomNavigation(i, context);
          },
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          enableFeedback: false,
          items: [
            _buildBottomNavItem(Icons.add, 'Add Files'),
            _buildBottomNavItem(Icons.info, 'Info'),
            _buildBottomNavItem(Icons.edit, 'Edit'),
            _buildBottomNavItem(Icons.check, 'Result'),
          ],
        ),
      ),
    );
  }
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:note_vision/widgets/drawer.dart';
import 'HomePage.dart';
import 'services/image_storage_service.dart'; // ← add this

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  int _currentIndex = 0;
  List<String> _imagePaths = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final service = ImageStorageService();
    final paths = await service.getSavedImages();
    if (mounted) {
      setState(() {
        _imagePaths = paths;
        _isLoading = false;
      });
    }
  }

  BottomNavigationBarItem _buildBottomNavItem(IconData icon, String label) {
    return BottomNavigationBarItem(icon: Icon(icon), label: label);
  }

  void _handleBottomNavigation(int index, BuildContext context) {
    if (index == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      ).then((_) => _loadImages()); // ← reload when returning from HomePage
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_imagePaths.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
                ).then((_) => _loadImages());
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
      );
    }

    // Grid of saved images
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        itemCount: _imagePaths.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (context, index) {
          final file = File(_imagePaths[index]);
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: const CollectionDrawer(),
      appBar: AppBar(
        key: const ValueKey('collectionAppBar'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('My Files', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: _buildBody(),
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
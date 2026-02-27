import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';   // still needed for types
import 'dart:io';

import 'image_picker_helper.dart';   // ← add this line

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  File? _selectedImage;

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.black),
      title: Text(title),
      onTap: onTap,
    );
  }

  Future<void> _handleScanSheet() async {
    final file = await ImagePickerHelper.pickFromCamera(context);
    if (file != null && mounted) {
      setState(() {
        _selectedImage = file;
      });
      // Optional: navigate, process OCR, etc.
    }
  }

  Future<void> _handleUploadImage() async {
    final file = await ImagePickerHelper.pickFromGallery(context);
    if (file != null && mounted) {
      setState(() {
        _selectedImage = file;
      });
      // Optional: same as above
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              color: Colors.black12,
              height: 48,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Text(
                'Menu',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            _buildDrawerItem(Icons.edit, 'Digital Writing', () {}),
            _buildDrawerItem(Icons.school, 'Instruction', () {}),
            _buildDrawerItem(Icons.info, 'About', () {}),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Image.asset(
            'assets/images/logo.png',
            height: 24,
          ),
        ),
        title: const Text(
          'Note Vision',
          style: TextStyle(
            fontFamily: 'MaturaMTScriptCapitals',
            fontSize: 24,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.black),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text(
              "Scan printed music sheets and convert them into editable digital notation with playback functionality.",
              style: TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 24),
            const Text(
              'Capture Music Sheet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.info_outline, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ensure the sheet is well-lit and fully visible for best detection accuracy.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  height: 400,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _selectedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.contain,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: Colors.grey,
                          size: 60,
                        ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF673AB7),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: _handleScanSheet,
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text('Scan Sheet', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF673AB7),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: _handleUploadImage,
                  icon: const Icon(Icons.upload_file, color: Colors.white),
                  label: const Text('Upload Image', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.black,
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
          },
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          enableFeedback: false,
          selectedLabelStyle: const TextStyle(color: Colors.white),
          unselectedLabelStyle: const TextStyle(color: Colors.white),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Scan'),
            BottomNavigationBarItem(icon: Icon(Icons.check), label: 'Result'),
            BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Files'),
          ],
        ),
      ),
    );
  }
}
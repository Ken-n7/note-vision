import 'package:flutter/material.dart';
import 'dart:io';

import 'package:note_vision/core/utils/image_picker_helper.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/features/scan/presentation/scan_screen.dart';


class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  File? _selectedImage;

  Future<void> _openCameraAndShowPreview() async {
    final file = await ImagePickerHelper.pickFromCamera(context);
    if (file == null || !mounted) return;

    setState(() {
      _selectedImage = file;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo captured — ready to process')),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    VoidCallback? onPressed,
    bool isOutlined = false,
  }) {
    final style = isOutlined
        ? OutlinedButton.styleFrom(
            foregroundColor: Colors.grey.shade800,
            side: BorderSide(color: Colors.grey.shade400),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF673AB7),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          );

    final textStyle = TextStyle(
      color: isOutlined ? Colors.grey.shade800 : Colors.white,
    );

    return isOutlined
        ? OutlinedButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label, style: textStyle),
          )
        : ElevatedButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white),
            label: Text(label, style: textStyle),
          );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            "Scan printed music sheets and convert them into editable digital notation with playback functionality.",
            style: TextStyle(fontSize: 16, color: Colors.black87),
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
                        child: Image.file(_selectedImage!, fit: BoxFit.contain),
                      )
                    : const Icon(
                        Icons.camera_alt,
                        color: Colors.grey,
                        size: 80,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _selectedImage == null
                ? [
                    _buildActionButton(
                      label: 'Scan Sheet',
                      icon: Icons.camera_alt,
                      onPressed: _openCameraAndShowPreview,
                    ),
                    _buildActionButton(
                      label: 'Upload Image',
                      icon: Icons.upload_file,
                      onPressed: () async {
                        final file = await ImagePickerHelper.pickFromGallery(
                          context,
                        );
                        if (file != null && mounted) {
                          setState(() => _selectedImage = file);
                        }
                      },
                    ),
                  ]
                : [
                    _buildActionButton(
                      label: 'Cancel',
                      icon: Icons.close,
                      isOutlined: true,
                      onPressed: () {
                        setState(() => _selectedImage = null);
                      },
                    ),
                    _buildActionButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward,
                      onPressed: () async {
                        final bytes = await _selectedImage!.readAsBytes();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ScanScreenProvider(imageBytes: bytes),
                          ),
                        );
                      },
                    ),
                  ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: const CollectionDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Image.asset('assets/images/logo.png', height: 24),
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
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color.fromARGB(255, 219, 215, 215),
          currentIndex: 0,
          onTap: (index) async {
            if (index == 0) {
              await _openCameraAndShowPreview();
            }
          },
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey.shade600,
          type: BottomNavigationBarType.fixed,
          enableFeedback: false,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Scan'),
            BottomNavigationBarItem(
              icon: Icon(Icons.upload_file),
              label: 'Import',
            ),
          ],
        ),
      ),
    );
  }
}

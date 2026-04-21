import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ImagePickerHelper {
  static Future<File?> pickFromCamera(BuildContext context) async {
    return _pickImage(context, ImageSource.camera);
  }

  static Future<File?> pickFromGallery(BuildContext context) async {
    return _pickImage(context, ImageSource.gallery);
  }

  static Future<File?> _pickImage(
    BuildContext context,
    ImageSource source,
  ) async {
    try {
      final picker = ImagePicker();

      final XFile? xFile = await picker.pickImage(
        source: source,
        imageQuality: 82, // adjustable 0–100
        maxWidth: 1200,
        maxHeight: 1200,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (xFile == null) return null;

      return File(xFile.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image\n$e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
  }
}

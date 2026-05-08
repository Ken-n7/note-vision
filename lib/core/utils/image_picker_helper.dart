import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ImagePickerHelper {
  // Formats the scan pipeline can decode (image package + iOS/Android native)
  static const _supportedExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'};

  static Future<File?> pickFromCamera(BuildContext context) async {
    return _pickImage(context, ImageSource.camera);
  }

  static Future<File?> pickFromGallery(BuildContext context) async {
    return _pickImage(context, ImageSource.gallery);
  }

  static Future<File?> _pickImage(BuildContext context, ImageSource source) async {
    try {
      final picker = ImagePicker();

      final XFile? xFile = await picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1200,
        maxHeight: 1200,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (xFile == null) return null;

      final ext = _extension(xFile.path);
      if (!_supportedExtensions.contains(ext)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Unsupported image format ($ext). Please use JPG, PNG, or WebP.',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return null;
      }

      return File(xFile.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot).toLowerCase();
  }
}
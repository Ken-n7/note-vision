import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ImageStorageService {
  static const String _key = 'saved_image_paths';

  /// Saves the image permanently and returns its path
  Future<String> saveImage(File imageFile) async {
    final dir = await getApplicationDocumentsDirectory();
    final String folderPath = path.join(dir.path, 'my_collection');
    final Directory collectionDir = Directory(folderPath);

    if (!await collectionDir.exists()) {
      await collectionDir.create(recursive: true);
    }

    final String fileName =
        '${DateTime.now().millisecondsSinceEpoch}${path.extension(imageFile.path)}';
    final String newPath = path.join(folderPath, fileName);

    final savedFile = await imageFile.copy(newPath);

    // Save path to shared preferences
    final prefs = await SharedPreferences.getInstance();
    final List<String> paths = prefs.getStringList(_key) ?? [];
    paths.add(savedFile.path);
    await prefs.setStringList(_key, paths);

    return savedFile.path;
  }

  /// Get all saved image paths (newest first)
  Future<List<String>> getSavedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> paths = prefs.getStringList(_key) ?? [];
    return paths.reversed.toList(); // newest on top
  }

  /// Optional: clear everything (for testing)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);

    final dir = await getApplicationDocumentsDirectory();
    final collectionDir = Directory(path.join(dir.path, 'my_collection'));
    if (await collectionDir.exists()) {
      await collectionDir.delete(recursive: true);
    }
  }
}
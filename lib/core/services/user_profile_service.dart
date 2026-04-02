import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  final String name;
  final String? photoPath;

  const UserProfile({
    required this.name,
    this.photoPath,
  });

  File? get photoFile {
    if (photoPath == null) return null;
    final file = File(photoPath!);
    return file.existsSync() ? file : null;
  }

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';
}

class UserProfileService {
  static const String _keyName = 'user_name';
  static const String _keyPhotoPath = 'user_photo_path';
  static const String _keyOnboardingComplete = 'onboarding_complete';

  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingComplete) ?? false;
  }

  static Future<UserProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyName);
    if (name == null || name.isEmpty) return null;

    final photoPath = prefs.getString(_keyPhotoPath);
    return UserProfile(name: name, photoPath: photoPath);
  }

  static Future<void> saveProfile({
    required String name,
    String? photoPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name.trim());

    if (photoPath != null) {
      await prefs.setString(_keyPhotoPath, photoPath);
    } else {
      await prefs.remove(_keyPhotoPath);
    }

    await prefs.setBool(_keyOnboardingComplete, true);
  }

  static Future<void> updateName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name.trim());
  }

  static Future<void> updatePhotoPath(String? photoPath) async {
    final prefs = await SharedPreferences.getInstance();
    if (photoPath != null) {
      await prefs.setString(_keyPhotoPath, photoPath);
    } else {
      await prefs.remove(_keyPhotoPath);
    }
  }
  
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    await prefs.remove(_keyPhotoPath);
    await prefs.remove(_keyOnboardingComplete);
  }
}
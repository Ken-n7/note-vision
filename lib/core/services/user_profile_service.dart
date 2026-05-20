import 'dart:math';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  final String name;
  final String? photoPath;

  const UserProfile({required this.name, this.photoPath});

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
  static const String _keyUserId = 'user_id';
  static const String _keyOnboardingComplete = 'onboarding_complete';
  static const String _keyRole = 'user_role';

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

  static Future<String?> loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRole);
  }

  static Future<String> loadOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyUserId);
    if (existing != null && existing.isNotEmpty) return existing;

    final userId = _generateUserId();
    await prefs.setString(_keyUserId, userId);
    return userId;
  }

  static String _generateUserId() {
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}$suffix';
  }

  static Future<void> saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRole, role);
  }

  static Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingComplete, true);
  }

  static Future<void> saveProfile({
    required String name,
    String? photoPath,
    bool completeOnboarding = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name.trim());
    if ((prefs.getString(_keyUserId) ?? '').isEmpty) {
      await prefs.setString(_keyUserId, _generateUserId());
    }

    if (photoPath != null) {
      await prefs.setString(_keyPhotoPath, photoPath);
    } else {
      await prefs.remove(_keyPhotoPath);
    }

    if (completeOnboarding) {
      await prefs.setBool(_keyOnboardingComplete, true);
    }
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
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyOnboardingComplete);
    await prefs.remove(_keyRole);
  }
}

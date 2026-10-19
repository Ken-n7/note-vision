import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_features.dart';
import '../models/project.dart';
import 'user_profile_service.dart';

/// Persists [Project] objects as individual JSON files. Classroom builds can
/// scope storage by the current role; presentation builds fall back to
/// `{appDocumentsDir}/projects/{id}.json`.
///
/// A lightweight role-scoped master index stored in [SharedPreferences] maps
/// project ids → names, allowing [loadAllProjects] to enumerate projects
/// without loading every file. The index is kept in sync with the filesystem
/// on every write/delete.
class ProjectStorageService {
  static const _indexKey = 'project_index';

  /// Overridable for testing — when null the real documents directory is used.
  final Future<Directory> Function()? _projectsDirOverride;
  final Future<String?> Function()? _roleProvider;
  Future<SharedPreferences>? _prefsFuture;

  ProjectStorageService({
    Future<Directory> Function()? projectsDirOverride,
    Future<String?> Function()? roleProvider,
  }) : _projectsDirOverride = projectsDirOverride,
       _roleProvider = roleProvider;

  // ── directory / file helpers ────────────────────────────────────────────

  Future<Directory> _projectsDir() async {
    final baseDir = _projectsDirOverride != null
        ? await _projectsDirOverride()
        : Directory(
            p.join((await getApplicationDocumentsDirectory()).path, 'projects'),
          );
    final scope = await _roleScope();
    final dir = scope == null
        ? baseDir
        : Directory(p.join(baseDir.path, scope));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String?> _roleScope() async {
    if (!AppFeatures.classroomWorkflow && _roleProvider == null) return null;
    final role = await (_roleProvider ?? UserProfileService.loadRole)();
    return role == 'teacher' || role == 'student' ? role : null;
  }

  Future<String> _indexKeyForScope() async {
    final scope = await _roleScope();
    return scope == null ? _indexKey : '${_indexKey}_$scope';
  }

  Future<File> _fileFor(String id) async {
    final dir = await _projectsDir();
    return File(p.join(dir.path, '$id.json'));
  }

  // ── public API ──────────────────────────────────────────────────────────

  /// Writes [project] to disk and updates the master index.
  /// If a file for [project.id] already exists it is overwritten.
  Future<void> saveProject(Project project) async {
    final file = await _fileFor(project.id);
    await file.writeAsString(jsonEncode(project.toJson()));
    await _upsertIndex(project.id, project.name);
  }

  /// Loads the project with [id] from disk. Returns null if the file does not
  /// exist (e.g. was deleted outside the app).
  Future<Project?> loadProject(String id) async {
    final file = await _fileFor(id);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return Project.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Returns all saved projects, sorted by [Project.updatedAt] descending
  /// (most-recently-saved first). Projects whose files are missing or
  /// unreadable are skipped, so one damaged file can't hide the rest.
  Future<List<Project>> loadAllProjects() async {
    final index = await _readIndex();
    final projects = <Project>[];
    for (final entry in index) {
      try {
        final project = await loadProject(entry['id']!);
        if (project != null) projects.add(project);
      } catch (e) {
        debugPrint('Skipping unreadable project ${entry['id']}: $e');
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  /// Deletes the JSON file for [id] and removes its entry from the master
  /// index. No-ops silently if the project does not exist.
  Future<void> deleteProject(String id) async {
    final file = await _fileFor(id);
    if (await file.exists()) await file.delete();
    await _removeFromIndex(id);
  }

  // ── index helpers ───────────────────────────────────────────────────────

  Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  Future<List<Map<String, String>>> _readIndex() async {
    final prefs = await _prefs();
    final raw = prefs.getString(await _indexKeyForScope());
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  Future<void> _writeIndex(List<Map<String, String>> index) async {
    final prefs = await _prefs();
    await prefs.setString(await _indexKeyForScope(), jsonEncode(index));
  }

  Future<void> _upsertIndex(String id, String name) async {
    final index = await _readIndex();
    index.removeWhere((e) => e['id'] == id);
    index.add({'id': id, 'name': name});
    await _writeIndex(index);
  }

  Future<void> _removeFromIndex(String id) async {
    final index = await _readIndex();
    index.removeWhere((e) => e['id'] == id);
    await _writeIndex(index);
  }
}

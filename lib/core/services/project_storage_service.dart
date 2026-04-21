import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';

/// Persists [Project] objects as individual JSON files under
/// `{appDocumentsDir}/projects/{id}.json`.
///
/// A lightweight master index stored in [SharedPreferences] under
/// [_indexKey] maps project ids → names, allowing [loadAllProjects] to
/// enumerate projects without loading every file. The index is kept in sync
/// with the filesystem on every write/delete.
class ProjectStorageService {
  static const _indexKey = 'project_index';

  /// Overridable for testing — when null the real documents directory is used.
  final Future<Directory> Function()? _projectsDirOverride;

  ProjectStorageService({Future<Directory> Function()? projectsDirOverride})
      : _projectsDirOverride = projectsDirOverride;

  // ── directory / file helpers ────────────────────────────────────────────

  Future<Directory> _projectsDir() async {
    if (_projectsDirOverride != null) return _projectsDirOverride();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'projects'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
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
  /// (most-recently-saved first). Projects whose files are missing are skipped.
  Future<List<Project>> loadAllProjects() async {
    final index = await _readIndex();
    final projects = <Project>[];
    for (final entry in index) {
      final project = await loadProject(entry['id']!);
      if (project != null) projects.add(project);
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

  Future<List<Map<String, String>>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  Future<void> _upsertIndex(String id, String name) async {
    final index = await _readIndex();
    index.removeWhere((e) => e['id'] == id);
    index.add({'id': id, 'name': name});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(index));
  }

  Future<void> _removeFromIndex(String id) async {
    final index = await _readIndex();
    index.removeWhere((e) => e['id'] == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(index));
  }
}

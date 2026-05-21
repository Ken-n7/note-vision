import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/services/project_storage_service.dart';

class NvscoreImportService {
  NvscoreImportService({ProjectStorageService? storageService})
    : _storage = storageService ?? ProjectStorageService();

  final ProjectStorageService _storage;

  Future<Project?> importProject({
    FutureOr<Project> Function(Project project)? beforeSave,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final bytes = await _readPickedBytes(result.files.single);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Selected file is not a Note Vision score.');
    }

    final parsedProject = Project.fromJson(decoded);
    final project = beforeSave == null
        ? parsedProject
        : await beforeSave(parsedProject);
    await _storage.saveProject(project);
    return project;
  }

  Future<Project?> importFromPath(
    String path, {
    FutureOr<Project> Function(Project project)? beforeSave,
  }) async {
    final bytes = await File(path).readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('File is not a Note Vision score.');
    }
    final parsedProject = Project.fromJson(decoded);
    final project =
        beforeSave == null ? parsedProject : await beforeSave(parsedProject);
    await _storage.saveProject(project);
    return project;
  }

  Future<Uint8List> _readPickedBytes(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null) return bytes;

    final path = file.path;
    if (path == null) {
      throw const FileSystemException('Could not read selected file.');
    }

    return File(path).readAsBytes();
  }
}

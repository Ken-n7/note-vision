import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/utils/export_file_name.dart';

class NvscoreExportService {
  const NvscoreExportService();

  Future<String?> exportProject(Project project, {String? fileName}) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(project.toJson())));
    final exportName = safeExportFileName(fileName ?? project.name);

    return FilePicker.platform.saveFile(
      fileName: '$exportName.nvscore',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['nvscore'],
    );
  }

  Future<String?> exportAllProjects(
    List<Project> projects, {
    String fileName = 'note_vision_scores',
  }) {
    final archive = Archive();
    final usedNames = <String, int>{};

    for (final project in projects) {
      final baseName = safeExportFileName(project.name);
      final count = usedNames.update(
        baseName,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final entryName = count == 0
          ? '$baseName.nvscore'
          : '${baseName}_$count.nvscore';
      final bytes = utf8.encode(jsonEncode(project.toJson()));
      archive.addFile(ArchiveFile.bytes(entryName, bytes));
    }

    final zipped = ZipEncoder().encode(archive);

    return FilePicker.platform.saveFile(
      fileName: '${safeExportFileName(fileName)}.zip',
      bytes: Uint8List.fromList(zipped),
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
  }

  static String submissionFileName({
    required Project project,
    required String studentName,
    required String studentId,
  }) {
    return 'submission_${safeExportFileName(studentName)}_${_shortId(studentId)}_${safeExportFileName(project.name)}_${_dateStamp()}';
  }

  static String feedbackFileName(Project project) {
    final student = project.submittedBy?.trim();
    final studentPart = student == null || student.isEmpty
        ? 'student'
        : safeExportFileName(student);
    return 'feedback_${studentPart}_${safeExportFileName(project.name)}_${_dateStamp()}';
  }

  static String collectionZipFileName({
    required String role,
    required String filter,
  }) {
    return 'note_vision_${safeExportFileName(role)}_${safeExportFileName(filter)}_${_dateStamp()}';
  }

  static String _shortId(String id) =>
      id.length <= 8 ? id : id.substring(id.length - 8);

  static String _dateStamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}';
  }
}

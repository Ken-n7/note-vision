import 'dart:convert';

import 'score.dart';

class Project {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The [Score] serialized as a JSON string. Call [decodeScore] to get it back.
  final String scoreJson;
  final String? submittedBy;
  final String? submittedById;
  final Map<int, String>? teacherComments;

  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.scoreJson,
    this.submittedBy,
    this.submittedById,
    this.teacherComments,
  });

  /// Creates a brand-new project from a [score]. The id is derived from the
  /// current epoch milliseconds — no UUID package needed.
  factory Project.create({
    required String name,
    required Score score,
    String? submittedBy,
    String? submittedById,
    Map<int, String>? teacherComments,
  }) {
    final now = DateTime.now();
    return Project(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: now,
      updatedAt: now,
      scoreJson: jsonEncode(score.toJson()),
      submittedBy: submittedBy,
      submittedById: submittedById,
      teacherComments: teacherComments,
    );
  }

  /// Returns a copy with an updated [name] and/or [score], and a refreshed
  /// [updatedAt] timestamp. Fields not provided are carried over unchanged.
  Project copyWithUpdated({
    String? name,
    Score? score,
    String? submittedBy,
    String? submittedById,
    Map<int, String>? teacherComments,
  }) => Project(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    scoreJson: score != null ? jsonEncode(score.toJson()) : scoreJson,
    submittedBy: submittedBy ?? this.submittedBy,
    submittedById: submittedById ?? this.submittedById,
    teacherComments: teacherComments ?? this.teacherComments,
  );

  /// Deserializes the embedded [scoreJson] back into a [Score].
  Score decodeScore() =>
      Score.fromJson(jsonDecode(scoreJson) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'scoreJson': scoreJson,
    if (submittedBy != null) 'submittedBy': submittedBy,
    if (submittedById != null) 'submittedById': submittedById,
    if (teacherComments != null && teacherComments!.isNotEmpty)
      'teacherComments': teacherComments!.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
  };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    scoreJson: json['scoreJson'] as String,
    submittedBy: json['submittedBy'] as String?,
    submittedById: json['submittedById'] as String?,
    teacherComments: json['teacherComments'] != null
        ? (json['teacherComments'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(int.parse(k), v as String),
          )
        : null,
  );
}

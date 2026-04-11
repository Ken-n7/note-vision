import 'dart:convert';

import 'score.dart';

class Project {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The [Score] serialized as a JSON string. Call [decodeScore] to get it back.
  final String scoreJson;

  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.scoreJson,
  });

  /// Creates a brand-new project from a [score]. The id is derived from the
  /// current epoch milliseconds — no UUID package needed.
  factory Project.create({required String name, required Score score}) {
    final now = DateTime.now();
    return Project(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: now,
      updatedAt: now,
      scoreJson: jsonEncode(score.toJson()),
    );
  }

  /// Returns a copy with an updated [name] and/or [score], and a refreshed
  /// [updatedAt] timestamp. Fields not provided are carried over unchanged.
  Project copyWithUpdated({String? name, Score? score}) => Project(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        scoreJson: score != null ? jsonEncode(score.toJson()) : scoreJson,
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
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        scoreJson: json['scoreJson'] as String,
      );
}

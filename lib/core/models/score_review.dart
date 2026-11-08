/// Portable scan evidence. Coordinates are fractions of the saved page.
class SourceRegion {
  const SourceRegion({
    required this.pageId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String pageId;
  final double x, y, width, height;

  Map<String, dynamic> toJson() => {
    'pageId': pageId,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory SourceRegion.fromJson(Map<String, dynamic> json) => SourceRegion(
    pageId: json['pageId'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
  );
}

/// Embedded once per scan so a saved/exported project keeps its evidence.
class ScoreSourcePage {
  const ScoreSourcePage({required this.id, required this.imageBase64});
  final String id;
  final String imageBase64;

  Map<String, dynamic> toJson() => {'id': id, 'imageBase64': imageBase64};
  factory ScoreSourcePage.fromJson(Map<String, dynamic> json) =>
      ScoreSourcePage(
        id: json['id'] as String,
        imageBase64: json['imageBase64'] as String,
      );
}

/// A detected mark that did not survive reconstruction as a written accidental.
/// Kept outside the musical symbols until a person assigns or ignores it.
class UnassignedAccidental {
  const UnassignedAccidental({
    required this.id,
    required this.alter,
    this.source,
  });

  final String id;
  final int alter;
  final SourceRegion? source;

  static const _keep = Object();

  UnassignedAccidental copyWith({
    String? id,
    int? alter,
    Object? source = _keep,
  }) => UnassignedAccidental(
    id: id ?? this.id,
    alter: alter ?? this.alter,
    source: identical(source, _keep) ? this.source : source as SourceRegion?,
  );

  String get name => switch (alter) {
    -2 => 'double flat',
    -1 => 'flat',
    0 => 'natural',
    1 => 'sharp',
    2 => 'double sharp',
    _ => 'accidental',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'alter': alter,
    if (source != null) 'source': source!.toJson(),
  };

  factory UnassignedAccidental.fromJson(Map<String, dynamic> json) =>
      UnassignedAccidental(
        id: json['id'] as String,
        alter: json['alter'] as int,
        source: json['source'] == null
            ? null
            : SourceRegion.fromJson(
                Map<String, dynamic>.from(json['source'] as Map),
              ),
      );
}

enum ReviewDisposition { applied, kept, deferred }

/// Lives with the score, so decisions participate in save/load and undo/redo.
class ScoreReviewEntry {
  const ScoreReviewEntry({
    required this.id,
    required this.issueKey,
    required this.fingerprint,
    required this.message,
    required this.location,
    required this.disposition,
    required this.createdAt,
    this.change,
    this.beforeMeasures = const {},
    this.afterMeasures = const {},
    this.beforePartOrder = const {},
    this.afterPartOrder = const {},
  });

  final String id, issueKey, fingerprint, message, location;
  final ReviewDisposition disposition;
  final DateTime createdAt;
  final String? change;

  /// Stable measure id -> serialized measure. Used for conflict-checked restore.
  final Map<String, Map<String, dynamic>> beforeMeasures, afterMeasures;
  final Map<String, List<String>> beforePartOrder, afterPartOrder;

  Map<String, dynamic> toJson() => {
    'id': id,
    'issueKey': issueKey,
    'fingerprint': fingerprint,
    'message': message,
    'location': location,
    'disposition': disposition.name,
    'createdAt': createdAt.toIso8601String(),
    if (change != null) 'change': change,
    if (beforeMeasures.isNotEmpty) 'beforeMeasures': beforeMeasures,
    if (afterMeasures.isNotEmpty) 'afterMeasures': afterMeasures,
    if (beforePartOrder.isNotEmpty) 'beforePartOrder': beforePartOrder,
    if (afterPartOrder.isNotEmpty) 'afterPartOrder': afterPartOrder,
  };

  factory ScoreReviewEntry.fromJson(Map<String, dynamic> json) {
    Map<String, Map<String, dynamic>> measures(String key) =>
        (json[key] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        );
    return ScoreReviewEntry(
      id: json['id'] as String,
      issueKey: json['issueKey'] as String,
      fingerprint: json['fingerprint'] as String,
      message: json['message'] as String,
      location: json['location'] as String,
      disposition: ReviewDisposition.values.byName(
        json['disposition'] as String,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      change: json['change'] as String?,
      beforeMeasures: measures('beforeMeasures'),
      afterMeasures: measures('afterMeasures'),
      beforePartOrder: (json['beforePartOrder'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, List<String>.from(v as List))),
      afterPartOrder: (json['afterPartOrder'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, List<String>.from(v as List))),
    );
  }
}

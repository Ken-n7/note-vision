import 'musical_time.dart';

/// Source timing includes notes the current editor cannot yet represent,
/// such as grace notes and unpitched percussion. Indices address the original
/// document, not the shorter list of editable symbols.
class SourceScoreEvent {
  const SourceScoreEvent({
    required this.partId,
    required this.measureIndex,
    required this.noteIndex,
    required this.onset,
    required this.duration,
    required this.voice,
    required this.staff,
    required this.isRest,
    required this.isGrace,
    required this.isChordTone,
  });

  final String partId, voice;
  final int measureIndex, noteIndex, staff;
  final MusicalTime onset, duration;
  final bool isRest, isGrace, isChordTone;

  factory SourceScoreEvent.fromJson(Map<String, dynamic> json) =>
      SourceScoreEvent(
        partId: json['partId'] as String,
        measureIndex: json['measureIndex'] as int,
        noteIndex: json['noteIndex'] as int,
        onset: MusicalTime.fromJson(
          Map<String, dynamic>.from(json['onset'] as Map),
        ),
        duration: MusicalTime.fromJson(
          Map<String, dynamic>.from(json['duration'] as Map),
        ),
        voice: json['voice'] as String,
        staff: json['staff'] as int,
        isRest: json['isRest'] as bool,
        isGrace: json['isGrace'] as bool,
        isChordTone: json['isChordTone'] as bool,
      );

  Map<String, dynamic> toJson() => {
    'partId': partId,
    'measureIndex': measureIndex,
    'noteIndex': noteIndex,
    'onset': onset.toJson(),
    'duration': duration.toJson(),
    'voice': voice,
    'staff': staff,
    'isRest': isRest,
    'isGrace': isGrace,
    'isChordTone': isChordTone,
  };
}

class MusicXmlSymbolBinding {
  const MusicXmlSymbolBinding({
    required this.symbolId,
    required this.partId,
    required this.measureIndex,
    required this.noteIndex,
  });
  final String symbolId, partId;
  final int measureIndex, noteIndex;

  factory MusicXmlSymbolBinding.fromJson(Map<String, dynamic> json) =>
      MusicXmlSymbolBinding(
        symbolId: json['symbolId'] as String,
        partId: json['partId'] as String,
        measureIndex: json['measureIndex'] as int,
        noteIndex: json['noteIndex'] as int,
      );
  Map<String, dynamic> toJson() => {
    'symbolId': symbolId,
    'partId': partId,
    'measureIndex': measureIndex,
    'noteIndex': noteIndex,
  };
}

/// A retained source document, distinct from the editor's supported projection.
/// Snapshots share this immutable object; save/load preserves it verbatim.
class MusicXmlSource {
  static const schemaVersion = 1;

  MusicXmlSource({
    required this.xml,
    required this.baselineJson,
    required Iterable<MusicXmlSymbolBinding> bindings,
    required Iterable<SourceScoreEvent> events,
    required this.requiresPreservation,
  }) : bindings = List.unmodifiable(bindings),
       events = List.unmodifiable(events);

  final String xml, baselineJson;
  final List<MusicXmlSymbolBinding> bindings;
  final List<SourceScoreEvent> events;
  final bool requiresPreservation;

  factory MusicXmlSource.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException(
        'Unsupported MusicXML source document version',
      );
    }
    return MusicXmlSource(
      xml: json['xml'] as String,
      baselineJson: json['baselineJson'] as String,
      bindings: (json['bindings'] as List).map(
        (b) =>
            MusicXmlSymbolBinding.fromJson(Map<String, dynamic>.from(b as Map)),
      ),
      events: (json['events'] as List).map(
        (e) => SourceScoreEvent.fromJson(Map<String, dynamic>.from(e as Map)),
      ),
      requiresPreservation: json['requiresPreservation'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'xml': xml,
    'baselineJson': baselineJson,
    'bindings': bindings.map((b) => b.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'requiresPreservation': requiresPreservation,
  };
}

/// Each voice's home staff in a part written on several staves: the staff
/// most of its notes sit on (the lower number on a tie). A note of that
/// voice on another staff is cross-staff: it keeps its voice's time and is
/// only drawn on the other staff.
Map<V, int> homeStaves<V>(Iterable<(V voice, int staff)> notes) {
  final counts = <V, Map<int, int>>{};
  for (final (voice, staff) in notes) {
    final byStaff = counts.putIfAbsent(voice, () => {});
    byStaff[staff] = (byStaff[staff] ?? 0) + 1;
  }
  return {
    for (final MapEntry(key: voice, value: byStaff) in counts.entries)
      voice: (byStaff.entries.toList()
            ..sort(
              (a, b) => a.value != b.value
                  ? b.value.compareTo(a.value)
                  : a.key.compareTo(b.key),
            ))
          .first
          .key,
  };
}

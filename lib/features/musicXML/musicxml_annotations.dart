import 'dart:convert';
import 'package:xml/xml.dart';
import '../../core/models/score_annotation.dart';
import '../../core/models/musical_time.dart';

/// Directions and harmonies retain their original XML. Only the modeled text,
/// tempo and chord fields change during an edit; other direction types survive.
abstract final class MusicXmlAnnotations {
  static String? text(XmlElement? e, String name) =>
      e?.getElement(name)?.innerText;
  static const navigationWords = {
    'fine',
    'to coda',
    'd.c.',
    'd.c. al fine',
    'd.c. al coda',
    'd.s.',
    'd.s. al fine',
    'd.s. al coda',
    'dc',
    'ds',
  };
  static ScoreAnnotation? read(XmlElement e, MusicalTime at, int index) {
    final types = e
        .findElements('direction-type')
        .expand((t) => t.childElements)
        .toList();
    final words = types
        .where((t) => t.name.local == 'words')
        .map((e) => e.innerText)
        .join(' ');
    final rehearsal = types
        .where((t) => t.name.local == 'rehearsal')
        .firstOrNull;
    final metro = types.where((t) => t.name.local == 'metronome').firstOrNull;
    final bpm = double.tryParse(text(metro, 'per-minute') ?? '');
    final sound = double.tryParse(
      e.getElement('sound')?.getAttribute('tempo') ?? '',
    );
    final tempo = sound != null && sound > 0 && sound.isFinite
        ? sound
        : bpm != null && bpm > 0 && bpm.isFinite
        ? bpm *
              beatQuarters(
                text(metro, 'beat-unit') ?? 'quarter',
                metro?.findElements('beat-unit-dot').length ?? 0,
              )
        : null;
    final harmony = e.name.local == 'harmony';
    final root = e.getElement('root');
    if (!harmony &&
        rehearsal == null &&
        metro == null &&
        tempo == null &&
        (words.isEmpty ||
            navigationWords.contains(words.trim().toLowerCase()))) {
      return null;
    }
    // Roman/Nashville and polychords remain in the source; do not misrepresent them.
    if (harmony && (root == null || e.findElements('kind').length != 1)) {
      return null;
    }
    if (harmony &&
        [
          text(root, 'root-alter'),
          text(e.getElement('bass'), 'bass-alter'),
        ].any((v) => v != null && int.tryParse(v) == null)) {
      return null;
    }
    final chord = !harmony
        ? null
        : ChordSymbol(
            root: text(root, 'root-step') ?? 'C',
            alter: int.tryParse(text(root, 'root-alter') ?? '') ?? 0,
            kind: text(e, 'kind') ?? 'major',
            kindText: e.getElement('kind')?.getAttribute('text'),
            bass: text(e.getElement('bass'), 'bass-step'),
            bassAlter:
                int.tryParse(text(e.getElement('bass'), 'bass-alter') ?? '') ??
                0,
          );
    return ScoreAnnotation(
      kind: harmony
          ? AnnotationKind.chord
          : tempo != null || metro != null
          ? AnnotationKind.tempo
          : rehearsal != null
          ? AnnotationKind.rehearsal
          : !{'only-top', 'also-top'}.contains(e.getAttribute('system'))
          ? AnnotationKind.staffText
          : AnnotationKind.systemText,
      text: rehearsal?.innerText ?? words,
      offset: at,
      tempo: tempo,
      perMinute: bpm,
      beatUnit: text(metro, 'beat-unit') ?? 'quarter',
      beatDots: metro?.findElements('beat-unit-dot').length ?? 0,
      chord: chord,
      staff: int.tryParse(text(e, 'staff') ?? '') ?? 1,
      below: e.getAttribute('placement') == 'below',
      hidden: e.getAttribute('print-object') == 'no',
      sourceIndex: index,
      sourceXml: e.toXmlString(),
    );
  }

  static double beatQuarters(String unit, int dots) {
    final base =
        const {
          'whole': 4.0,
          'half': 2.0,
          'quarter': 1.0,
          'eighth': 0.5,
          '16th': 0.25,
        }[unit] ??
        1;
    var factor = 1.0, extra = 0.5;
    for (var i = 0; i < dots; i++) {
      factor += extra;
      extra /= 2;
    }
    return base * factor;
  }

  /// Source cursor and divisions at each element, including backup/forward.
  static Map<XmlElement, (MusicalTime, MusicalTime)> positions(
    XmlElement measure,
    MusicalTime divisions,
  ) {
    var cursor = MusicalTime.zero;
    final result = <XmlElement, (MusicalTime, MusicalTime)>{};
    for (final e in measure.childElements) {
      if (e.name.local == 'attributes' && text(e, 'divisions') != null) {
        divisions = MusicalTime.decimal(text(e, 'divisions')!);
      }
      result[e] = (cursor, divisions);
      final duration =
          MusicalTime.decimal(text(e, 'duration') ?? '0') / divisions;
      if (e.name.local == 'backup') cursor -= duration;
      if (e.name.local == 'forward' ||
          (e.name.local == 'note' &&
              e.getElement('chord') == null &&
              e.getElement('grace') == null)) {
        cursor += duration;
      }
    }
    return result;
  }

  static List<ScoreAnnotation> readMeasure(XmlElement m, double divisions) {
    final places = positions(m, MusicalTime.decimal('$divisions'));
    return [
      for (final (i, e) in m.childElements.indexed)
        if (e.name.local == 'direction' || e.name.local == 'harmony')
          ?read(
            e,
            places[e]!.$1 +
                MusicalTime.decimal(text(e, 'offset') ?? '0') / places[e]!.$2,
            i,
          ),
    ];
  }

  static void setText(XmlElement parent, String name, String? value) {
    final old = parent.getElement(name);
    if (value == null) {
      if (old != null) parent.children.remove(old);
      return;
    }
    final child = old ?? XmlElement(XmlName(name));
    child.children
      ..clear()
      ..add(XmlText(value));
    if (old == null) parent.children.add(child);
  }

  static String offsetText(MusicalTime offset) {
    var denominator = offset.denominator;
    for (final factor in [2, 5]) {
      while (denominator % factor == 0) {
        denominator ~/= factor;
      }
    }
    final value = offset.asDouble
        .toStringAsFixed(9)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    if (denominator != 1 || MusicalTime.decimal(value) != offset) {
      throw const FormatException(
        'This beat cannot be represented exactly with the imported divisions. Saving the project keeps the marking.',
      );
    }
    return value;
  }

  static XmlElement write(
    ScoreAnnotation a, {
    required MusicalTime cursor,
    required MusicalTime divisions,
    int? staff,
  }) {
    final e = a.sourceXml == null
        ? XmlElement(
            XmlName(a.kind == AnnotationKind.chord ? 'harmony' : 'direction'),
          )
        : XmlDocument.parse(a.sourceXml!).rootElement.copy();
    final before = a.sourceXml == null
        ? null
        : read(e, a.offset, a.sourceIndex ?? 0);
    if (before == null || before.below != a.below) {
      e.setAttribute('placement', a.below ? 'below' : 'above');
    }
    if (a.kind == AnnotationKind.chord) {
      final c = a.chord!;
      if (before?.chord?.toJson().toString() != c.toJson().toString()) {
        final root = e.getElement('root') ?? XmlElement(XmlName('root'));
        setText(root, 'root-step', c.root);
        setText(root, 'root-alter', c.alter == 0 ? null : '${c.alter}');
        final bass = e.getElement('bass') ?? XmlElement(XmlName('bass'));
        setText(bass, 'bass-step', c.bass);
        setText(bass, 'bass-alter', c.bassAlter == 0 ? null : '${c.bassAlter}');
        e.children.removeWhere(
          (n) =>
              n is XmlElement &&
              {'root', 'kind', 'bass'}.contains(n.name.local),
        );
        e.children.insertAll(0, [
          root,
          XmlElement(
            XmlName('kind'),
            [
              if (c.kindText != null)
                XmlAttribute(XmlName('text'), c.kindText!),
            ],
            [XmlText(c.kind)],
          ),
          if (c.bass != null) bass,
        ]);
      }
    } else {
      void replaceType(String name, List<XmlElement> replacements) {
        for (final type in e.findElements('direction-type').toList()) {
          type.children.removeWhere(
            (n) => n is XmlElement && n.name.local == name,
          );
          if (type.childElements.isEmpty) e.children.remove(type);
        }
        for (final replacement in replacements.reversed) {
          e.children.insert(
            0,
            XmlElement(XmlName('direction-type'), [], [replacement]),
          );
        }
      }

      if (before == null || before.text != a.text || before.kind != a.kind) {
        final name = a.kind == AnnotationKind.rehearsal ? 'rehearsal' : 'words';
        final original =
            e.findAllElements(name).firstOrNull?.copy() ??
            XmlElement(XmlName(name));
        original.children
          ..clear()
          ..add(XmlText(a.text));
        replaceType(name, [if (a.text.isNotEmpty) original]);
      }
      if (before == null ||
          before.perMinute != a.perMinute ||
          before.beatUnit != a.beatUnit ||
          before.beatDots != a.beatDots) {
        replaceType('metronome', [
          if (a.perMinute != null)
            XmlElement(XmlName('metronome'), [], [
              XmlElement(XmlName('beat-unit'), [], [XmlText(a.beatUnit)]),
              for (var i = 0; i < a.beatDots; i++)
                XmlElement(XmlName('beat-unit-dot')),
              XmlElement(XmlName('per-minute'), [], [
                XmlText(ScoreAnnotation.number(a.perMinute!)),
              ]),
            ]),
        ]);
      }
      if (before == null || before.tempo != a.tempo) {
        var sound = e.getElement('sound');
        if (sound == null && a.tempo != null) {
          sound = XmlElement(XmlName('sound'));
          e.children.add(sound);
        }
        sound?.setAttribute(
          'tempo',
          a.tempo == null ? null : ScoreAnnotation.number(a.tempo!),
        );
        if (e.findElements('direction-type').isEmpty) {
          e.children.insert(
            0,
            XmlElement(XmlName('direction-type'), [], [
              XmlElement(XmlName('words')),
            ]),
          );
        }
      }
      if (before == null && a.system) e.setAttribute('system', 'only-top');
    }
    final offset = (a.offset - cursor) * divisions;
    // Move offset and staff to their MusicXML schema positions.
    e.children.removeWhere(
      (n) => n is XmlElement && {'offset', 'staff'}.contains(n.name.local),
    );
    final tail = e.children.indexWhere(
      (n) =>
          n is XmlElement &&
          {
            'footnote',
            'level',
            'voice',
            'sound',
            'listening',
          }.contains(n.name.local),
    );
    e.children.insert(
      tail < 0 ? e.children.length : tail,
      XmlElement(XmlName('offset'), [], [XmlText(offsetText(offset))]),
    );
    final end = e.children.indexWhere(
      (n) => n is XmlElement && {'sound', 'listening'}.contains(n.name.local),
    );
    e.children.insert(
      end < 0 ? e.children.length : end,
      XmlElement(XmlName('staff'), [], [XmlText('${staff ?? a.staff}')]),
    );
    return e;
  }

  static bool same(List<ScoreAnnotation> a, List<ScoreAnnotation> b) =>
      jsonEncode(a.map((v) => v.toJson()).toList()) ==
      jsonEncode(b.map((v) => v.toJson()).toList());
}

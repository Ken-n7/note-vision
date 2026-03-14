import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:xml/xml.dart';

/// Converts a validated MusicXML document into internal score models.
class MusicXmlScoreConverter {
  const MusicXmlScoreConverter();

  Score convert(XmlDocument document) {
    final root = document.rootElement;

    final title = _readTitle(root);
    final composer = _readComposer(root);
    final partNamesById = _readPartNames(root);
    final parts = root.name.local == 'score-timewise'
        ? _buildTimewiseParts(root, partNamesById)
        : _buildPartwiseParts(root, partNamesById);

    return Score(
      id: root.getAttribute('id') ?? root.name.local,
      title: title,
      composer: composer,
      parts: parts,
    );
  }

  List<Part> _buildPartwiseParts(
    XmlElement root,
    Map<String, String> partNamesById,
  ) {
    return root.findElements('part').map((partElement) {
      final partId = partElement.getAttribute('id') ?? 'unknown-part';
      final partName = partNamesById[partId] ?? partId;
      final measures = partElement.findElements('measure').map(_buildMeasure).toList();

      return Part(id: partId, name: partName, measures: measures);
    }).toList();
  }

  List<Part> _buildTimewiseParts(
    XmlElement root,
    Map<String, String> partNamesById,
  ) {
    final measuresByPartId = <String, List<Measure>>{};

    for (final measureElement in root.findElements('measure')) {
      final measureNumber = int.tryParse(measureElement.getAttribute('number') ?? '') ?? 0;

      for (final partInMeasure in measureElement.findElements('part')) {
        final partId = partInMeasure.getAttribute('id') ?? 'unknown-part';
        final rebuiltMeasure = _buildMeasure(
          partInMeasure,
          explicitNumber: measureNumber,
        );
        measuresByPartId.putIfAbsent(partId, () => <Measure>[]).add(rebuiltMeasure);
      }
    }

    return measuresByPartId.entries.map((entry) {
      final partId = entry.key;
      final partName = partNamesById[partId] ?? partId;

      return Part(id: partId, name: partName, measures: entry.value);
    }).toList();
  }

  String _readTitle(XmlElement root) {
    final workElement = _firstOrNull(root.findElements('work'));
    final workTitle = _firstInnerText(workElement, 'work-title')?.trim();

    if (workTitle != null && workTitle.isNotEmpty) {
      return workTitle;
    }

    final movementTitle = _firstInnerText(root, 'movement-title')?.trim();
    if (movementTitle != null && movementTitle.isNotEmpty) {
      return movementTitle;
    }

    return 'Untitled';
  }

  String _readComposer(XmlElement root) {
    final identification = _firstOrNull(root.findElements('identification'));
    if (identification == null) {
      return 'Unknown composer';
    }

    for (final creator in identification.findElements('creator')) {
      if (creator.getAttribute('type') == 'composer') {
        final value = creator.innerText.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return 'Unknown composer';
  }

  Map<String, String> _readPartNames(XmlElement root) {
    final partNamesById = <String, String>{};

    final partList = _firstOrNull(root.findElements('part-list'));
    if (partList == null) {
      return partNamesById;
    }

    for (final scorePart in partList.findElements('score-part')) {
      final id = scorePart.getAttribute('id');
      final partName = _firstInnerText(scorePart, 'part-name')?.trim();
      if (id != null && id.isNotEmpty && partName != null && partName.isNotEmpty) {
        partNamesById[id] = partName;
      }
    }

    return partNamesById;
  }

  Measure _buildMeasure(XmlElement measureElement, {int? explicitNumber}) {
    final number = explicitNumber ?? int.tryParse(measureElement.getAttribute('number') ?? '') ?? 0;

    final attributes = _firstOrNull(measureElement.findElements('attributes'));
    final clef = _buildClef(attributes);
    final timeSignature = _buildTimeSignature(attributes);
    final keySignature = _buildKeySignature(attributes);

    final symbols = <ScoreSymbol>[];

    for (final noteElement in measureElement.findElements('note')) {
      final symbol = _buildSymbol(noteElement);
      if (symbol != null) {
        symbols.add(symbol);
      }
    }

    return Measure(
      number: number,
      clef: clef,
      timeSignature: timeSignature,
      keySignature: keySignature,
      symbols: symbols,
    );
  }

  ScoreSymbol? _buildSymbol(XmlElement noteElement) {
    final duration = int.tryParse(_firstInnerText(noteElement, 'duration') ?? '');
    final type = _firstInnerText(noteElement, 'type')?.trim();

    if (duration == null || type == null || type.isEmpty) {
      return null;
    }

    final voice = int.tryParse(_firstInnerText(noteElement, 'voice') ?? '');
    final staff = int.tryParse(_firstInnerText(noteElement, 'staff') ?? '');

    if (noteElement.findElements('rest').isNotEmpty) {
      return Rest(duration: duration, type: type, voice: voice, staff: staff);
    }

    final pitch = _firstOrNull(noteElement.findElements('pitch'));
    if (pitch == null) {
      return null;
    }

    final step = _firstInnerText(pitch, 'step')?.trim();
    final octave = int.tryParse(_firstInnerText(pitch, 'octave') ?? '');
    final alter = int.tryParse(_firstInnerText(pitch, 'alter') ?? '');

    if (step == null || step.isEmpty || octave == null) {
      return null;
    }

    return Note(
      step: step,
      octave: octave,
      alter: alter,
      duration: duration,
      type: type,
      voice: voice,
      staff: staff,
    );
  }

  Clef? _buildClef(XmlElement? attributes) {
    final clefElement = attributes == null ? null : _firstOrNull(attributes.findElements('clef'));
    if (clefElement == null) {
      return null;
    }

    final sign = _firstInnerText(clefElement, 'sign')?.trim();
    final line = int.tryParse(_firstInnerText(clefElement, 'line') ?? '');
    if (sign == null || sign.isEmpty || line == null) {
      return null;
    }

    return Clef(sign: sign, line: line);
  }

  TimeSignature? _buildTimeSignature(XmlElement? attributes) {
    final timeElement = attributes == null ? null : _firstOrNull(attributes.findElements('time'));
    if (timeElement == null) {
      return null;
    }

    final beats = int.tryParse(_firstInnerText(timeElement, 'beats') ?? '');
    final beatType = int.tryParse(_firstInnerText(timeElement, 'beat-type') ?? '');
    if (beats == null || beatType == null) {
      return null;
    }

    return TimeSignature(beats: beats, beatType: beatType);
  }

  KeySignature? _buildKeySignature(XmlElement? attributes) {
    final keyElement = attributes == null ? null : _firstOrNull(attributes.findElements('key'));
    if (keyElement == null) {
      return null;
    }

    final fifths = int.tryParse(_firstInnerText(keyElement, 'fifths') ?? '');
    if (fifths == null) {
      return null;
    }

    return KeySignature(fifths: fifths);
  }

  XmlElement? _firstOrNull(Iterable<XmlElement> elements) {
    return elements.isEmpty ? null : elements.first;
  }

  String? _firstInnerText(XmlElement? parent, String tagName) {
    if (parent == null) {
      return null;
    }
    final child = _firstOrNull(parent.findElements(tagName));
    return child?.innerText;
  }
}

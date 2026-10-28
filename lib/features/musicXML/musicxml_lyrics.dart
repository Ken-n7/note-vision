import 'package:xml/xml.dart';
import '../../core/models/lyric.dart';

/// Shared by generated export and the retained-source patcher.
abstract final class MusicXmlLyrics {
  static Lyric read(XmlElement e) => Lyric(
    verse: e.getAttribute('number') ?? '1',
    text: e.childElements
        .where((c) => {'text', 'elision'}.contains(c.name.local))
        .map((c) => c.innerText)
        .join(),
    syllabic: Syllabic.values.firstWhere(
      (v) => v.name == e.getElement('syllabic')?.innerText.trim(),
      orElse: () => Syllabic.single,
    ),
    extend: e.getElement('extend') == null
        ? null
        : switch (e.getElement('extend')!.getAttribute('type')) {
            'stop' => LyricExtend.stop,
            'continue' => LyricExtend.continueLine,
            _ => LyricExtend.start,
          },
    above: e.getAttribute('placement') == 'above',
    hidden: e.getAttribute('print-object') == 'no',
    sourceXml: e.toXmlString(),
  );

  static XmlElement write(Lyric lyric) {
    final e = lyric.sourceXml == null
        ? XmlElement(XmlName('lyric'))
        : XmlDocument.parse(lyric.sourceXml!).rootElement.copy();
    final before = lyric.sourceXml == null ? null : read(e);
    e.setAttribute('number', lyric.verse);
    if (before == null || before.above != lyric.above) {
      e.setAttribute('placement', lyric.above ? 'above' : 'below');
    }
    if (before == null || before.hidden != lyric.hidden) {
      e.setAttribute('print-object', lyric.hidden ? 'no' : null);
    }
    if (before == null ||
        before.text != lyric.text ||
        before.syllabic != lyric.syllabic) {
      final textElement =
          e.getElement('text')?.copy() ?? XmlElement(XmlName('text'));
      textElement.children
        ..clear()
        ..add(XmlText(lyric.text));
      e.children.removeWhere(
        (c) =>
            c is XmlElement &&
            {'text', 'elision', 'syllabic'}.contains(c.name.local),
      );
      if (lyric.text.isNotEmpty) {
        e.children.insertAll(0, [
          XmlElement(XmlName('syllabic'), [], [XmlText(lyric.syllabic.name)]),
          textElement,
        ]);
      }
    }
    if (before == null || before.extend != lyric.extend) {
      e.children.removeWhere(
        (c) => c is XmlElement && c.name.local == 'extend',
      );
      if (lyric.extend != null) {
        final extension = XmlElement(XmlName('extend'), [
          XmlAttribute(XmlName('type'), switch (lyric.extend!) {
            LyricExtend.continueLine => 'continue',
            final v => v.name,
          }),
        ]);
        final index = e.children.indexWhere(
          (c) =>
              c is XmlElement &&
              {
                'end-line',
                'end-paragraph',
                'footnote',
                'level',
              }.contains(c.name.local),
        );
        e.children.insert(index < 0 ? e.children.length : index, extension);
      }
    }
    return e;
  }
}

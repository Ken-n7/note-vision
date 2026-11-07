// Center-only diagnostic on locally supplied MUSCIMA++ annotation boxes.
// NV_CENTER_MPP=<root with annotations/ and images/> NV_CENTER_WORK=<output>
//   flutter test --no-pub tool/notehead_center_eval_test.dart
// Uses labelled head/stem unions and the labelled head end. This is not model
// inference, an unseen-photo benchmark, or a complete musical-pitch oracle.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/data/notehead_center_finder.dart';
import 'package:xml/xml.dart';

typedef _Node = ({String kind, Rect box, List<int> links});

void main() {
  test('annotated head centering diagnostic', timeout: Timeout.none, () {
    final root = Platform.environment['NV_CENTER_MPP'];
    final output = Platform.environment['NV_CENTER_WORK'];
    if (root == null || output == null) return;
    final pages =
        Directory('$root/annotations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.xml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final results = <Map<String, Object>>[];
    for (final page in pages) {
      final name = page.uri.pathSegments.last.replaceFirst('.xml', '');
      final writer = int.parse(name.split('W-')[1].substring(0, 2));
      final nodes = <int, _Node>{};
      for (final e in XmlDocument.parse(
        page.readAsStringSync(),
      ).findAllElements('Node')) {
        String text(String key) => e.getElement(key)?.innerText ?? '';
        double number(String key) => double.parse(text(key));
        nodes[int.parse(text('Id'))] = (
          kind: text('ClassName'),
          box: Rect.fromLTWH(
            number('Left'),
            number('Top'),
            number('Width'),
            number('Height'),
          ),
          links: [
            for (final s in text('Outlinks').trim().split(RegExp(r'\s+')))
              if (s.isNotEmpty) int.parse(s),
          ],
        );
      }
      final headsOnStem = <int, int>{};
      for (final node in nodes.values.where(
        (n) => n.kind.startsWith('notehead'),
      )) {
        for (final id in node.links.where((id) => nodes[id]?.kind == 'stem')) {
          headsOnStem[id] = (headsOnStem[id] ?? 0) + 1;
        }
      }
      final image = img.invert(
        img.decodePng(File('$root/images/$name.png').readAsBytesSync())!,
      );
      for (final entry in nodes.entries) {
        final node = entry.value;
        if (node.kind != 'noteheadFull') continue;
        final stems = node.links
            .where((id) => nodes[id]?.kind == 'stem')
            .toList();
        if (stems.length != 1 ||
            headsOnStem[stems.single] != 1 ||
            !node.links.any((id) => nodes[id]?.kind == 'beam')) {
          continue;
        }
        final head = node.box, stem = nodes[stems.single]!.box;
        final full = Rect.fromLTRB(
          math.min(head.left, stem.left),
          math.min(head.top, stem.top),
          math.max(head.right, stem.right),
          math.max(head.bottom, stem.bottom),
        );
        final upper = head.center.dy < full.center.dy;
        final band = Rect.fromLTWH(
          full.left,
          upper ? full.top : full.bottom - full.height * .3,
          full.width,
          full.height * .3,
        );
        final estimate = Rect.fromCenter(
          center: band.center,
          width: full.width,
          height: full.height * .16,
        );
        final refined = const NoteheadCenterFinder().refine(
          image,
          band: band,
          estimate: estimate,
        );
        results.add({
          'page': name,
          'id': entry.key,
          'writer': writer,
          'before': (estimate.center.dy - head.center.dy).abs() / head.height,
          'after': (refined.center.dy - head.center.dy).abs() / head.height,
          'fitted': !identical(refined, estimate),
        });
      }
    }
    Map<String, Object?> summarize(List<Map<String, Object>> rows) {
      final fits = rows.where((r) => r['fitted'] == true).toList();
      double value(Map<String, Object> row, String key) => row[key] as double;
      double? mean(List<Map<String, Object>> rs, String key) => rs.isEmpty
          ? null
          : rs.fold<double>(0, (sum, r) => sum + value(r, key)) / rs.length;
      return {
        'notes': rows.length,
        'fitted': fits.length,
        'meanBefore': mean(rows, 'before'),
        'meanAfter': mean(rows, 'after'),
        'fitMeanBefore': mean(fits, 'before'),
        'fitMeanAfter': mean(fits, 'after'),
        'improved': fits
            .where((r) => value(r, 'after') < value(r, 'before') - 1e-8)
            .length,
        'worse': fits
            .where((r) => value(r, 'after') > value(r, 'before') + 1e-8)
            .length,
        'worseOverQuarterHead': fits
            .where((r) => value(r, 'after') - value(r, 'before') > .25)
            .length,
      };
    }

    final report = {
      'all': summarize(results),
      'writersEven': summarize(
        results.where((r) => (r['writer'] as int).isEven).toList(),
      ),
      'writersOdd': summarize(
        results.where((r) => (r['writer'] as int).isOdd).toList(),
      ),
    };
    Directory(output).createSync(recursive: true);
    File(
      '$output/mpp-dart-results.json',
    ).writeAsStringSync(jsonEncode(results));
    File(
      '$output/mpp-dart-summary.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print(jsonEncode(report));
  });
}

import 'dart:convert';

import '../models/measure.dart';
import '../models/note.dart';
import '../models/rest.dart';
import '../models/score.dart';
import '../models/score_review.dart';
import '../models/score_symbol.dart';
import 'notation_checker.dart';

class ReviewChange {
  const ReviewChange(
    this.partIndex,
    this.measureIndex,
    this.before,
    this.after,
  );
  final int partIndex, measureIndex;
  final Measure? before, after;
}

class NotationReviewPlan {
  const NotationReviewPlan({
    required this.base,
    required this.preview,
    required this.entries,
    required this.changes,
    required this.skipped,
  });
  final Score base, preview;
  final List<ScoreReviewEntry> entries;
  final List<ReviewChange> changes;
  final int skipped;
  bool get hasChanges => entries.isNotEmpty;
  String get scopeDescription {
    final staves = changes.map((c) => c.partIndex).toSet().length;
    return 'Changes ${changes.length} ${changes.length == 1 ? 'measure' : 'measures'}'
        ' across $staves ${staves == 1 ? 'staff' : 'staves'}.';
  }

  /// Never apply a preview prepared for a different revision of the score.
  Score? applyTo(Score current) => identical(current, base) && hasChanges
      ? preview.copyWith(reviewHistory: [...current.reviewHistory, ...entries])
      : null;

  /// Match the same surrounding music even when a bar split changes indices.
  (int, int) passageBounds(
    int partIndex, {
    required bool proposed,
    bool surrounding = true,
  }) {
    final score = proposed ? preview : base;
    final measures = score.parts[partIndex].measures;
    final indices = <int>[];
    for (final change in changes.where((c) => c.partIndex == partIndex)) {
      final target = proposed ? change.after : change.before;
      if (target == null) continue;
      final index = measures.indexWhere((m) => m.reviewId == target.reviewId);
      if (index >= 0) indices.add(index);
    }
    if (indices.isEmpty) return (0, 0);
    final first = indices.reduce((a, b) => a < b ? a : b);
    final last = indices.reduce((a, b) => a > b ? a : b);
    return (
      surrounding ? (first - 1).clamp(0, first) : first,
      surrounding ? (last + 1).clamp(last, measures.length - 1) : last,
    );
  }

  List<String> describe(ReviewChange change) {
    String? id(ScoreSymbol symbol) => switch (symbol) {
      Note(:final reviewId) || Rest(:final reviewId) => reviewId,
      _ => null,
    };
    String name(ScoreSymbol symbol) => switch (symbol) {
      Note(:final pitch, :final type, :final dots) =>
        '${dots > 0 ? 'dotted ' : ''}$type note ($pitch)',
      Rest(:final type, :final dots) =>
        '${dots > 0 ? 'dotted ' : ''}$type rest',
      _ => 'symbol',
    };
    Map<String?, (String?, int, ScoreSymbol)> symbols(Score score) => {
      for (final part in score.parts)
        for (final measure in part.measures)
          for (final symbol in measure.symbols)
            id(symbol): (measure.reviewId, measure.number, symbol),
    };
    final old = symbols(base), next = symbols(preview);
    final result = <String>[];
    for (final symbol in change.after?.symbols ?? <ScoreSymbol>[]) {
      final previous = old[id(symbol)];
      if (previous == null) {
        result.add('Added: ${name(symbol)}');
      } else if (previous.$1 != change.after!.reviewId) {
        result.add('Moved from measure ${previous.$2}: ${name(symbol)}');
      } else {
        final before = previous.$3.toJson()
          ..remove('source')
          ..remove('reviewId');
        final after = symbol.toJson()
          ..remove('source')
          ..remove('reviewId');
        if (jsonEncode(before) != jsonEncode(after)) {
          result.add('Changed: ${name(previous.$3)} → ${name(symbol)}');
        }
      }
    }
    for (final symbol in change.before?.symbols ?? <ScoreSymbol>[]) {
      final after = next[id(symbol)];
      if (after == null) {
        result.add('Removed: ${name(symbol)}');
      } else if (after.$1 != change.before!.reviewId) {
        result.add('Moved to measure ${after.$2}: ${name(symbol)}');
      }
    }
    return result.isEmpty ? ['Updated measure notation.'] : result;
  }
}

/// Review decisions are keyed by stable targets AND their musical context.
/// Moving a bar does not lose the decision; changing its contents reopens it.
class NotationReviewService {
  NotationReviewService._();
  static int _serial = 0;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_serial++}';

  static Score ensureIdentity(Score score) {
    final needsIdentity = score.parts.any(
      (p) => p.measures.any(
        (m) =>
            m.reviewId == null ||
            m.symbols.any(
              (s) => switch (s) {
                Note(:final reviewId) ||
                Rest(:final reviewId) => reviewId == null,
                _ => false,
              },
            ),
      ),
    );
    if (!needsIdentity) return score;
    var changed = false;
    final json = score.toJson();
    for (final part in json['parts'] as List) {
      for (final measure in part['measures'] as List) {
        if (measure['reviewId'] == null) {
          measure['reviewId'] = newId();
          changed = true;
        }
        for (final symbol in measure['symbols'] as List) {
          if ((symbol['symbolType'] == 'note' ||
                  symbol['symbolType'] == 'rest') &&
              symbol['reviewId'] == null) {
            symbol['reviewId'] = newId();
            changed = true;
          }
        }
      }
    }
    return changed ? Score.fromJson(json) : score;
  }

  static String key(Score score, NotationIssue issue) {
    final measure = score.parts[issue.partIndex].measures[issue.measureIndex];
    final symbol = issue.symbolIndex == null
        ? null
        : measure.symbols[issue.symbolIndex!];
    final symbolId = switch (symbol) {
      Note(:final reviewId) => reviewId,
      Rest(:final reviewId) => reviewId,
      _ => null,
    };
    return '${issue.kind.name}:${score.parts[issue.partIndex].id}:'
        '${measure.reviewId ?? issue.measureIndex}:${issue.unassignedAccidental?.id ?? symbolId ?? issue.symbolIndex ?? '-'}';
  }

  static Map<String, dynamic> _musical(Measure measure) {
    final json = measure.toJson()
      ..remove('number')
      ..remove('source')
      ..remove('reviewId');
    json['symbols'] = measure.symbols
        .map(
          (s) => s.toJson()
            ..remove('source')
            ..remove('reviewId'),
        )
        .toList();
    return json;
  }

  static String fingerprint(Score score, NotationIssue issue) {
    final measures = score.parts[issue.partIndex].measures;
    final m = issue.measureIndex;
    Object? clef, meter, keySignature;
    for (var i = 0; i <= m; i++) {
      clef = measures[i].clef?.toJson() ?? clef;
      meter = measures[i].timeSignature?.toJson() ?? meter;
      keySignature = measures[i].keySignature?.toJson() ?? keySignature;
    }
    // A meter proposal depends on the section; barline proposals on neighbors.
    final relevant = issue.kind == NotationIssueKind.timeSignature
        ? measures
        : measures.sublist(
            (m - 1).clamp(0, m),
            (m + 2).clamp(m + 1, measures.length),
          );
    return jsonEncode([
      clef,
      meter,
      keySignature,
      relevant.map(_musical).toList(),
    ]);
  }

  static NotationIssue setupIssue(int part, int measure) => NotationIssue(
    kind: NotationIssueKind.scanContext,
    partIndex: part,
    measureIndex: measure,
    message:
        'Compare the clef, sharps/flats, time signature and barlines with the photo. '
        'Also check for missing notes and stacked notes that should sound together.',
  );

  static bool _matches(Score score, NotationIssue issue, ScoreReviewEntry e) =>
      e.issueKey == key(score, issue) &&
      e.fingerprint == fingerprint(score, issue);

  static bool isDeferred(Score score, NotationIssue issue) =>
      score.reviewHistory.any(
        (e) =>
            e.disposition == ReviewDisposition.deferred &&
            _matches(score, issue, e),
      );

  static bool setupChecked(Score score, int part, int measure) =>
      !score.isScannedMusic ||
      score.reviewHistory.any(
        (e) =>
            e.disposition == ReviewDisposition.kept &&
            _matches(score, setupIssue(part, measure), e),
      );

  static List<NotationIssue> issues(Score score) {
    final result =
        [
              if (score.isScannedMusic)
                for (final (p, part) in score.parts.indexed)
                  if (!part.linked)
                    for (final (m, measure) in part.measures.indexed)
                      if (!measure.unresolvedBarlines &&
                          measure.symbols.any((s) => s is Note || s is Rest))
                        setupIssue(p, m),
              ...NotationChecker.check(score),
            ]
            .where(
              (issue) => !score.reviewHistory.any(
                (e) =>
                    e.disposition == ReviewDisposition.kept &&
                    _matches(score, issue, e),
              ),
            )
            .toList();
    result.sort((a, b) {
      final later = (isDeferred(score, a) ? 1 : 0).compareTo(
        isDeferred(score, b) ? 1 : 0,
      );
      if (later != 0) return later;
      final part = a.partIndex.compareTo(b.partIndex);
      if (part != 0) return part;
      final bar = a.measureIndex.compareTo(b.measureIndex);
      if (bar != 0) return bar;
      final priority = a.kind.index.compareTo(b.kind.index);
      return priority != 0
          ? priority
          : (a.symbolIndex ?? -1).compareTo(b.symbolIndex ?? -1);
    });
    return result;
  }

  /// Deferral leaves every question unresolved, and travels with save/export.
  static Score deferBar(Score score, NotationIssue issue) {
    var next = score;
    for (final i in issues(score).where(
      (i) =>
          i.partIndex == issue.partIndex &&
          i.measureIndex == issue.measureIndex,
    )) {
      if (isDeferred(next, i)) continue;
      next = _decision(next, i, ReviewDisposition.deferred);
    }
    return next;
  }

  static Score resumeBar(Score score, NotationIssue issue) {
    final keys = issues(score)
        .where(
          (i) =>
              i.partIndex == issue.partIndex &&
              i.measureIndex == issue.measureIndex,
        )
        .map((i) => key(score, i))
        .toSet();
    return score.copyWith(
      reviewHistory: score.reviewHistory
          .where(
            (e) =>
                e.disposition != ReviewDisposition.deferred ||
                !keys.contains(e.issueKey),
          )
          .toList(),
    );
  }

  static Score _decision(
    Score score,
    NotationIssue issue,
    ReviewDisposition disposition,
  ) => score.copyWith(
    reviewHistory: [
      ...score.reviewHistory.where(
        (e) =>
            e.disposition != ReviewDisposition.deferred ||
            e.issueKey != key(score, issue),
      ),
      ScoreReviewEntry(
        id: newId(),
        issueKey: key(score, issue),
        fingerprint: fingerprint(score, issue),
        message: issue.message,
        location: location(score, issue),
        disposition: disposition,
        createdAt: DateTime.now(),
      ),
    ],
  );

  static String location(Score score, NotationIssue issue) =>
      score.isScannedMusic
      ? 'Row ${issue.partIndex + 1} · ${score.parts[issue.partIndex].measures[issue.measureIndex].unresolvedBarlines ? 'Barlines unconfirmed' : 'Bar ${score.parts[issue.partIndex].measures[issue.measureIndex].number}'}'
      : 'Measure ${score.parts[issue.partIndex].measures[issue.measureIndex].number}'
            ' · ${score.parts[issue.partIndex].name}';

  static Score keep(Score score, NotationIssue issue) {
    final issueKey = key(score, issue), context = fingerprint(score, issue);
    if (score.reviewHistory.any(
      (e) =>
          e.disposition == ReviewDisposition.kept &&
          e.issueKey == issueKey &&
          e.fingerprint == context,
    )) {
      return score;
    }
    return _decision(score, issue, ReviewDisposition.kept);
  }

  /// Explicitly bind one preserved scan mark to a note in the reviewed bar.
  /// The caller records this alongside ordinary corrections for undo/restore.
  static Score? assignAccidental(Score score, NotationIssue issue, int index) {
    final mark = issue.unassignedAccidental;
    if (issue.kind != NotationIssueKind.unassignedAccidental ||
        mark == null ||
        !const [-2, -1, 0, 1, 2].contains(mark.alter) ||
        issue.partIndex < 0 ||
        issue.partIndex >= score.parts.length) {
      return null;
    }
    final part = score.parts[issue.partIndex];
    if (issue.measureIndex < 0 || issue.measureIndex >= part.measures.length) {
      return null;
    }
    final bar = part.measures[issue.measureIndex];
    if (index < 0 || index >= bar.symbols.length) return null;
    final note = bar.symbols[index];
    final matches = bar.unassignedAccidentals
        .where((a) => a.id == mark.id)
        .toList();
    if (note is! Note ||
        matches.length != 1 ||
        jsonEncode(matches.single.toJson()) != jsonEncode(mark.toJson())) {
      return null;
    }
    final symbols = [...bar.symbols]
      ..[index] = note.copyWith(alter: mark.alter);
    final bars = [...part.measures]
      ..[issue.measureIndex] = bar.copyWith(
        symbols: symbols,
        unassignedAccidentals: bar.unassignedAccidentals
            .where((a) => a.id != mark.id)
            .toList(),
      );
    final parts = [...score.parts]
      ..[issue.partIndex] = part.copyWith(measures: bars);
    return score.copyWith(parts: parts);
  }

  static NotationReviewPlan prepare(Score score, Set<String> selectedKeys) {
    var preview = score;
    final entries = <ScoreReviewEntry>[];
    var skipped = 0;
    final original = issues(
      score,
    ).where((i) => selectedKeys.contains(key(score, i))).toList();
    for (final issue in original) {
      final targetKey = key(score, issue);
      final current = issues(
        preview,
      ).where((i) => key(preview, i) == targetKey).firstOrNull;
      // Re-check after each change. An altered suggestion needs another review.
      if (current == null ||
          !current.hasFix ||
          fingerprint(preview, current) != fingerprint(score, issue)) {
        skipped++;
        continue;
      }
      if (!setupChecked(preview, current.partIndex, current.measureIndex)) {
        skipped++;
        continue;
      }
      final fixed = current.fix!(preview);
      if (identical(fixed, preview)) {
        skipped++;
        continue;
      }
      final next = ensureIdentity(fixed);
      final changes = diff(preview, next);
      if (changes.isEmpty) {
        skipped++;
        continue;
      }
      if (score.isScannedMusic &&
          changes.any(
            (c) =>
                c.before != null &&
                !setupChecked(
                  preview,
                  c.partIndex,
                  preview.parts[c.partIndex].measures.indexOf(c.before!),
                ),
          )) {
        skipped++;
        continue;
      }
      entries.add(_changeEntry(preview, next, current, current.fixLabel));
      preview = next;
    }
    return NotationReviewPlan(
      base: score,
      preview: preview,
      entries: entries,
      changes: diff(score, preview),
      skipped: skipped,
    );
  }

  static ScoreReviewEntry _changeEntry(
    Score preview,
    Score next,
    NotationIssue current,
    String? label,
  ) {
    final changes = diff(preview, next);
    return ScoreReviewEntry(
      id: newId(),
      issueKey: key(preview, current),
      fingerprint: fingerprint(preview, current),
      message: current.message,
      location: location(preview, current),
      disposition: ReviewDisposition.applied,
      createdAt: DateTime.now(),
      change: label,
      beforeMeasures: {
        for (final c in changes)
          if (c.before?.reviewId != null)
            c.before!.reviewId!: c.before!.toJson(),
      },
      beforePartOrder: {
        for (var p = 0; p < preview.parts.length; p++)
          if (jsonEncode(
                preview.parts[p].measures.map((m) => m.reviewId).toList(),
              ) !=
              jsonEncode(
                next.parts[p].measures.map((m) => m.reviewId).toList(),
              ))
            preview.parts[p].id: preview.parts[p].measures
                .map((m) => m.reviewId!)
                .toList(),
      },
      afterPartOrder: {
        for (var p = 0; p < next.parts.length; p++)
          if (jsonEncode(
                preview.parts[p].measures.map((m) => m.reviewId).toList(),
              ) !=
              jsonEncode(
                next.parts[p].measures.map((m) => m.reviewId).toList(),
              ))
            next.parts[p].id: next.parts[p].measures
                .map((m) => m.reviewId!)
                .toList(),
      },
      afterMeasures: {
        for (final c in changes)
          if (c.after?.reviewId != null) c.after!.reviewId!: c.after!.toJson(),
      },
    );
  }

  /// A direct user correction uses the same preview, history and restore path.
  static NotationReviewPlan correction(
    Score score,
    Score changed,
    NotationIssue issue,
    String label,
  ) {
    final next = ensureIdentity(changed);
    final changes = diff(score, next);
    return NotationReviewPlan(
      base: score,
      preview: next,
      entries: changes.isEmpty ? [] : [_changeEntry(score, next, issue, label)],
      changes: changes,
      skipped: 0,
    );
  }

  static List<ReviewChange> diff(Score before, Score after) {
    final result = <ReviewChange>[];
    for (var p = 0; p < after.parts.length; p++) {
      final old = p < before.parts.length
          ? before.parts[p].measures
          : <Measure>[];
      final next = after.parts[p].measures;
      final byId = {for (final m in old) m.reviewId: m};
      final oldContexts = _contexts(old);
      final nextContexts = _contexts(next);
      for (var m = 0; m < next.length; m++) {
        final previous = byId[next[m].reviewId];
        if (previous == null ||
            jsonEncode(_musical(previous)) != jsonEncode(_musical(next[m])) ||
            oldContexts[previous.reviewId] != nextContexts[next[m].reviewId]) {
          result.add(ReviewChange(p, m, previous, next[m]));
        }
      }
      final nextIds = next.map((m) => m.reviewId).toSet();
      for (var m = 0; m < old.length; m++) {
        if (!nextIds.contains(old[m].reviewId)) {
          result.add(ReviewChange(p, m, old[m], null));
        }
      }
    }
    return result;
  }

  static Map<String?, String> _contexts(List<Measure> measures) {
    Object? clef, meter, keySignature;
    return {
      for (final measure in measures)
        measure.reviewId: jsonEncode([
          clef = measure.clef?.toJson() ?? clef,
          meter = measure.timeSignature?.toJson() ?? meter,
          keySignature = measure.keySignature?.toJson() ?? keySignature,
        ]),
    };
  }

  /// Restore only an unchanged patch. Structural restores also check measure
  /// ordering, so subsequent insertions or edits are never overwritten.
  static bool canRestore(Score score, ScoreReviewEntry entry) {
    if (entry.disposition != ReviewDisposition.applied) return true;
    if (entry.beforeMeasures.isEmpty) return false;
    final structural =
        entry.beforeMeasures.keys
            .toSet()
            .difference(entry.afterMeasures.keys.toSet())
            .isNotEmpty ||
        entry.afterMeasures.keys
            .toSet()
            .difference(entry.beforeMeasures.keys.toSet())
            .isNotEmpty;
    if (structural && entry.afterPartOrder.isEmpty) return false;
    for (final order in entry.afterPartOrder.entries) {
      final part = score.parts.where((p) => p.id == order.key).firstOrNull;
      if (part == null ||
          jsonEncode(part.measures.map((m) => m.reviewId).toList()) !=
              jsonEncode(order.value)) {
        return false;
      }
    }
    final current = {
      for (final p in score.parts)
        for (final m in p.measures)
          if (m.reviewId != null) m.reviewId!: m,
    };
    return entry.afterMeasures.entries.every(
      (e) =>
          current[e.key] != null &&
          jsonEncode(_musical(current[e.key]!)) ==
              jsonEncode(_musical(Measure.fromJson(e.value))),
    );
  }

  static Score? restore(Score score, ScoreReviewEntry entry) {
    if (!canRestore(score, entry)) return null;
    final history = score.reviewHistory.where((e) => e.id != entry.id).toList();
    if (entry.disposition != ReviewDisposition.applied) {
      return score.copyWith(reviewHistory: history);
    }
    return score.copyWith(
      parts: [
        for (final part in score.parts)
          () {
            final order = entry.beforePartOrder[part.id];
            if (order == null) {
              return part.copyWith(
                measures: [
                  for (final measure in part.measures)
                    if (entry.beforeMeasures.containsKey(measure.reviewId))
                      Measure.fromJson({
                        ...entry.beforeMeasures[measure.reviewId]!,
                        'number': measure.number,
                      })
                    else
                      measure,
                ],
              );
            }
            final measures = {for (final m in part.measures) m.reviewId: m};
            return part.copyWith(
              measures: [
                for (var index = 0; index < order.length; index++)
                  if (entry.beforeMeasures.containsKey(order[index]))
                    Measure.fromJson({
                      ...entry.beforeMeasures[order[index]]!,
                      'number': index + 1,
                    })
                  else if (measures.containsKey(order[index]))
                    Measure.fromJson({
                      ...measures[order[index]]!.toJson(),
                      'number': index + 1,
                    }),
              ],
            );
          }(),
      ],
      reviewHistory: history,
    );
  }

  static SourceRegion? sourceOf(ScoreSymbol? symbol) => switch (symbol) {
    Note(:final source) => source,
    Rest(:final source) => source,
    _ => null,
  };

  static SourceRegion? measureSource(Measure measure, {String? pageId}) {
    final sources = [
      ...measure.symbols.map(sourceOf).whereType<SourceRegion>(),
      ...measure.unassignedAccidentals
          .map((a) => a.source)
          .whereType<SourceRegion>(),
    ];
    final page =
        pageId ?? sources.firstOrNull?.pageId ?? measure.source?.pageId;
    final own = sources.where((s) => s.pageId == page).toList();
    if (own.isEmpty) return measure.source;
    final left = own.map((s) => s.x).reduce((a, b) => a < b ? a : b);
    final top = own.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final right = own.map((s) => s.x + s.width).reduce((a, b) => a > b ? a : b);
    final bottom = own
        .map((s) => s.y + s.height)
        .reduce((a, b) => a > b ? a : b);
    return SourceRegion(
      pageId: page!,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  static String title(NotationIssueKind kind) => switch (kind) {
    NotationIssueKind.scanContext => 'Check this bar against the photo',
    NotationIssueKind.unassignedAccidental => 'Assign this accidental',
    NotationIssueKind.lowConfidence => 'Check this symbol',
    NotationIssueKind.missingComponent => 'Check the notation',
    NotationIssueKind.misplacedAccidental => 'Check this accidental',
    NotationIssueKind.beatTotal => 'Check the rhythm',
    NotationIssueKind.timeSignature => 'Check the time signature',
  };
}

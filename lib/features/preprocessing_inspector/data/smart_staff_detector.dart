import 'dart:math' as math;

import '../../detection/domain/detection_result.dart';
import '../../detection/domain/music_symbol.dart';
import 'dev_staff_line_detector.dart';

enum SmartStaffSource { modelOnly, heuristicOnly, fused }
enum SmartStaffConfidence { confirmed, probable, weak, reject }

class SmartStaffCandidate {
  const SmartStaffCandidate({
    required this.observedLineYs,
    required this.inferredLineYs,
    required this.lineConfidences,
    required this.repairMethods,
    required this.source,
    required this.countScore,
    required this.spacingScore,
    required this.overlapScore,
    required this.projectionScore,
    required this.thicknessScore,
    required this.penaltyScore,
    required this.score,
    required this.confidence,
  });

  final List<double> observedLineYs;
  final List<double> inferredLineYs;
  final List<double> lineConfidences;
  final List<String> repairMethods;

  final SmartStaffSource source;
  final double countScore;
  final double spacingScore;
  final double overlapScore;
  final double projectionScore;
  final double thicknessScore;
  final double penaltyScore;
  final double score;
  final SmartStaffConfidence confidence;

  List<double> get lineYs => [...observedLineYs, ...inferredLineYs]..sort();
}

class SmartStaffDetectionResult {
  const SmartStaffDetectionResult({
    required this.candidates,
    required this.modelCount,
    required this.heuristicCount,
  });

  final List<SmartStaffCandidate> candidates;
  final int modelCount;
  final int heuristicCount;
}

class SmartStaffDetector {
  const SmartStaffDetector();

  static const _createThreshold = 0.62;
  static const _repairThreshold = 0.48;

  SmartStaffDetectionResult detect({
    required DetectionResult modelDetection,
    required DevStaffLineDetectionResult heuristic,
  }) {
    final modelGroups = modelDetection.staffs.map((s) => s.lineYs).toList();
    final heuristicGroups =
        heuristic.groups.map((g) => g.lines.map((l) => l.y).toList()).toList();

    final heuristicByY = {
      for (final g in heuristic.groups)
        ...g.lines.map((line) => MapEntry(line.y, line)),
    };

    final combBoxes = modelDetection.symbols
        .where((s) => s.musicSymbol == MusicSymbol.combStaff)
        .map((s) => _SymbolBox(top: s.y, bottom: s.y + (s.height ?? 0), height: s.height ?? 0))
        .where((b) => b.height > 0)
        .toList(growable: false);

    final usedHeuristic = <int>{};
    final candidates = <SmartStaffCandidate>[];

    for (final modelLines in modelGroups) {
      final modelCenter = _centerY(modelLines);
      var bestIndex = -1;
      var bestDistance = double.infinity;

      for (var i = 0; i < heuristicGroups.length; i++) {
        if (usedHeuristic.contains(i)) continue;
        final distance = (_centerY(heuristicGroups[i]) - modelCenter).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = i;
        }
      }

      if (bestIndex != -1 && bestDistance <= 12) {
        usedHeuristic.add(bestIndex);
        candidates.add(
          _scoreCandidate(
            observed: _fuseObserved(modelLines, heuristicGroups[bestIndex]),
            source: SmartStaffSource.fused,
            combBoxes: combBoxes,
            heuristicByY: heuristicByY,
          ),
        );
      } else {
        candidates.add(
          _scoreCandidate(
            observed: modelLines,
            source: SmartStaffSource.modelOnly,
            combBoxes: combBoxes,
            heuristicByY: heuristicByY,
          ),
        );
      }
    }

    for (var i = 0; i < heuristicGroups.length; i++) {
      if (usedHeuristic.contains(i)) continue;
      candidates.add(
        _scoreCandidate(
          observed: heuristicGroups[i],
          source: SmartStaffSource.heuristicOnly,
          combBoxes: combBoxes,
          heuristicByY: heuristicByY,
        ),
      );
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    return SmartStaffDetectionResult(
      candidates: candidates,
      modelCount: modelGroups.length,
      heuristicCount: heuristicGroups.length,
    );
  }

  SmartStaffCandidate _scoreCandidate({
    required List<double> observed,
    required SmartStaffSource source,
    required List<_SymbolBox> combBoxes,
    required Map<double, DevStaffLine> heuristicByY,
  }) {
    final observedSorted = [...observed]..sort();

    final countScore = (observedSorted.length / 5).clamp(0.0, 1.0);
    final spacingScore = _spacingScore(observedSorted);
    final overlapScore = _combOverlapScore(observedSorted, combBoxes);
    final projectionScore = _projectionScore(observedSorted, heuristicByY);
    final thicknessScore = _thicknessScore(observedSorted, heuristicByY);
    final penaltyScore = _penaltyScore(observedSorted, spacingScore);

    var baseScore = (0.20 * countScore) +
        (0.20 * spacingScore) +
        (0.20 * overlapScore) +
        (0.20 * projectionScore) +
        (0.20 * thicknessScore) -
        (0.25 * penaltyScore);

    baseScore = baseScore.clamp(0.0, 1.0);

    final inferred = <double>[];
    final repairMethods = <String>[];
    final confidences = List<double>.filled(observedSorted.length, baseScore.clamp(0.55, 0.95));

    // Hysteresis: looser for repair than new candidate creation.
    if (observedSorted.length >= 3 &&
        observedSorted.length < 5 &&
        baseScore >= _repairThreshold) {
      final repaired = _inferMissingLines(observedSorted);
      inferred.addAll(repaired.inferred);
      repairMethods.addAll(repaired.methods);
      confidences.addAll(List<double>.filled(repaired.inferred.length, 0.58));
      baseScore = (baseScore + 0.08).clamp(0.0, 1.0);
    }

    final confidence = _labelFromScore(baseScore, observedSorted.length + inferred.length);

    return SmartStaffCandidate(
      observedLineYs: observedSorted,
      inferredLineYs: inferred,
      lineConfidences: confidences,
      repairMethods: repairMethods,
      source: source,
      countScore: countScore,
      spacingScore: spacingScore,
      overlapScore: overlapScore,
      projectionScore: projectionScore,
      thicknessScore: thicknessScore,
      penaltyScore: penaltyScore,
      score: baseScore,
      confidence: confidence,
    );
  }

  SmartStaffConfidence _labelFromScore(double score, int lineCount) {
    if (lineCount >= 5 && score >= 0.80) return SmartStaffConfidence.confirmed;
    if (score >= _createThreshold) return SmartStaffConfidence.probable;
    if (score >= _repairThreshold) return SmartStaffConfidence.weak;
    return SmartStaffConfidence.reject;
  }

  ({List<double> inferred, List<String> methods}) _inferMissingLines(List<double> observed) {
    if (observed.length < 3 || observed.length >= 5) {
      return (inferred: const <double>[], methods: const <String>[]);
    }

    final gaps = <double>[];
    for (var i = 0; i < observed.length - 1; i++) {
      gaps.add(observed[i + 1] - observed[i]);
    }
    final avgGap = gaps.isEmpty ? 0.0 : gaps.reduce((a, b) => a + b) / gaps.length;
    if (avgGap <= 0) {
      return (inferred: const <double>[], methods: const <String>[]);
    }

    final inferred = <double>[];
    final methods = <String>[];
    var working = [...observed];

    while (working.length + inferred.length < 5) {
      final topCandidate = working.first - avgGap;
      final bottomCandidate = working.last + avgGap;

      // Alternate top/bottom growth to avoid directional bias.
      if (inferred.length.isEven) {
        inferred.add(topCandidate);
        methods.add('spacing_projection_top');
      } else {
        inferred.add(bottomCandidate);
        methods.add('spacing_projection_bottom');
      }
      working = [...working, ...inferred]..sort();
    }

    inferred.sort();
    return (inferred: inferred, methods: methods);
  }

  List<double> _fuseObserved(List<double> model, List<double> heur) {
    final count = math.min(model.length, heur.length);
    if (count == 0) return model;

    final fused = <double>[];
    for (var i = 0; i < count; i++) {
      fused.add((model[i] * 0.7) + (heur[i] * 0.3));
    }
    fused.sort();
    return fused;
  }

  double _spacingScore(List<double> lineYs) {
    if (lineYs.length < 2) return 0.0;
    final gaps = <double>[];
    for (var i = 0; i < lineYs.length - 1; i++) {
      gaps.add(lineYs[i + 1] - lineYs[i]);
    }
    final avg = gaps.reduce((a, b) => a + b) / gaps.length;
    if (avg <= 0) return 0.0;
    final variance = gaps.fold<double>(0.0, (sum, g) => sum + math.pow(g - avg, 2)) / gaps.length;
    final std = math.sqrt(variance);
    return (1 - (std / avg)).clamp(0.0, 1.0);
  }

  double _combOverlapScore(List<double> lineYs, List<_SymbolBox> combBoxes) {
    if (lineYs.isEmpty) return 0.0;
    if (combBoxes.isEmpty) return 0.4;

    final minY = lineYs.first;
    final maxY = lineYs.last;

    var best = 0.0;
    for (final box in combBoxes) {
      final insideCount = lineYs.where((y) => y >= box.top && y <= box.bottom).length;
      final ratio = insideCount / lineYs.length;

      final expectedHeight = (lineYs.length >= 2)
          ? (lineYs.last - lineYs.first)
          : box.height;
      final heightMismatch = (box.height - expectedHeight).abs() / (box.height + 1e-6);
      final heightScore = (1 - heightMismatch).clamp(0.0, 1.0);

      final spanScore = ((math.min(maxY, box.bottom) - math.max(minY, box.top)) /
              (maxY - minY + 1e-6))
          .clamp(0.0, 1.0);

      final score = (ratio * 0.5) + (heightScore * 0.3) + (spanScore * 0.2);
      if (score > best) best = score;
    }
    return best;
  }

  double _projectionScore(List<double> lineYs, Map<double, DevStaffLine> heuristicByY) {
    if (lineYs.isEmpty) return 0.0;
    var sum = 0.0;

    for (final y in lineYs) {
      final nearest = _nearestHeuristic(y, heuristicByY.values.toList());
      if (nearest == null) continue;
      sum += nearest.darknessRatio.clamp(0.0, 1.0);
    }

    return (sum / lineYs.length).clamp(0.0, 1.0);
  }

  double _thicknessScore(List<double> lineYs, Map<double, DevStaffLine> heuristicByY) {
    final thicknesses = <double>[];
    for (final y in lineYs) {
      final nearest = _nearestHeuristic(y, heuristicByY.values.toList());
      if (nearest != null) thicknesses.add(nearest.thickness.toDouble());
    }
    if (thicknesses.length < 2) return 0.6;

    final avg = thicknesses.reduce((a, b) => a + b) / thicknesses.length;
    if (avg <= 0) return 0.0;
    final variance = thicknesses.fold<double>(0, (s, t) => s + math.pow(t - avg, 2)) /
        thicknesses.length;
    final std = math.sqrt(variance);
    return (1 - (std / avg)).clamp(0.0, 1.0);
  }

  double _penaltyScore(List<double> lineYs, double spacingScore) {
    var penalty = 0.0;
    if (lineYs.length < 3) penalty += 0.6;
    if (spacingScore < 0.45) penalty += 0.3;
    if (lineYs.length > 6) penalty += 0.2;
    return penalty.clamp(0.0, 1.0);
  }

  DevStaffLine? _nearestHeuristic(double y, List<DevStaffLine> lines) {
    if (lines.isEmpty) return null;
    lines.sort((a, b) => (a.y - y).abs().compareTo((b.y - y).abs()));
    return lines.first;
  }
}

class _SymbolBox {
  const _SymbolBox({required this.top, required this.bottom, required this.height});

  final double top;
  final double bottom;
  final double height;
}

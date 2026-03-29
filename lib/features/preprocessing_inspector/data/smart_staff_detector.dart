import '../../detection/domain/detection_result.dart';
import 'dev_staff_line_detector.dart';

enum SmartStaffSource { modelOnly, heuristicOnly, fused }

class SmartStaffCandidate {
  const SmartStaffCandidate({
    required this.lineYs,
    required this.score,
    required this.source,
  });

  final List<double> lineYs;
  final double score;
  final SmartStaffSource source;
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

  SmartStaffDetectionResult detect({
    required DetectionResult modelDetection,
    required DevStaffLineDetectionResult heuristic,
  }) {
    final modelGroups = modelDetection.staffs.map((s) => s.lineYs).toList();
    final heuristicGroups = heuristic.groups.map((g) => g.lines.map((l) => l.y).toList()).toList();

    final usedHeuristic = <int>{};
    final candidates = <SmartStaffCandidate>[];

    for (final modelLines in modelGroups) {
      final modelCenter = _centerY(modelLines);
      var bestIndex = -1;
      var bestDistance = double.infinity;

      for (var i = 0; i < heuristicGroups.length; i++) {
        if (usedHeuristic.contains(i)) continue;
        final heurLines = heuristicGroups[i];
        final distance = (_centerY(heurLines) - modelCenter).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = i;
        }
      }

      if (bestIndex != -1 && bestDistance <= 12) {
        final heurLines = heuristicGroups[bestIndex];
        usedHeuristic.add(bestIndex);
        final fused = <double>[];
        final count = modelLines.length < heurLines.length ? modelLines.length : heurLines.length;
        for (var j = 0; j < count; j++) {
          fused.add((modelLines[j] * 0.7) + (heurLines[j] * 0.3));
        }
        candidates.add(
          SmartStaffCandidate(
            lineYs: fused,
            score: _scoreFromDistance(bestDistance, fused.length),
            source: SmartStaffSource.fused,
          ),
        );
      } else {
        candidates.add(
          SmartStaffCandidate(
            lineYs: modelLines,
            score: 0.7,
            source: SmartStaffSource.modelOnly,
          ),
        );
      }
    }

    for (var i = 0; i < heuristicGroups.length; i++) {
      if (usedHeuristic.contains(i)) continue;
      candidates.add(
        SmartStaffCandidate(
          lineYs: heuristicGroups[i],
          score: 0.5,
          source: SmartStaffSource.heuristicOnly,
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

  double _centerY(List<double> lineYs) {
    if (lineYs.isEmpty) return 0;
    return lineYs.reduce((a, b) => a + b) / lineYs.length;
  }

  double _scoreFromDistance(double distance, int lineCount) {
    final d = (1.0 - (distance / 20)).clamp(0.0, 1.0);
    final l = (lineCount / 5).clamp(0.0, 1.0);
    return (d * 0.7) + (l * 0.3);
  }
}

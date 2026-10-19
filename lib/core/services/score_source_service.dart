import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/score.dart';
import '../models/score_review.dart';
import 'notation_review_service.dart';

/// A compressed copy of the orientation-corrected scan travels with the score.
/// Normalized coordinates continue to work when the evidence image is resized.
class ScoreSourceService {
  ScoreSourceService._();

  static Future<Score> attach(
    Score score,
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    final hasEvidence = score.parts.any(
      (p) => p.measures.any(
        (m) => m.symbols.any((s) => NotationReviewService.sourceOf(s) != null),
      ),
    );
    if (!hasEvidence || width <= 0 || height <= 0) {
      return NotationReviewService.ensureIdentity(score);
    }
    final encoded = await compute(_compress, bytes);
    if (encoded == null) return NotationReviewService.ensureIdentity(score);
    final pageId = NotationReviewService.newId();
    final json = score.toJson();
    for (final part in json['parts'] as List) {
      for (final measure in part['measures'] as List) {
        final regions = <Map<String, dynamic>>[];
        for (final symbol in measure['symbols'] as List) {
          final source = symbol['source'] as Map<String, dynamic>?;
          if (source == null) continue;
          source['pageId'] = pageId;
          source['x'] = ((source['x'] as num) / width).clamp(0.0, 1.0);
          source['y'] = ((source['y'] as num) / height).clamp(0.0, 1.0);
          source['width'] = ((source['width'] as num) / width).clamp(0.0, 1.0);
          source['height'] = ((source['height'] as num) / height).clamp(
            0.0,
            1.0,
          );
          symbol['reviewId'] = '$pageId:${symbol['reviewId']}';
          regions.add(source);
        }
        if (regions.isNotEmpty) {
          final left = regions.map((r) => r['x'] as double).reduce(math.min);
          final top = regions.map((r) => r['y'] as double).reduce(math.min);
          final right = regions
              .map((r) => (r['x'] as double) + (r['width'] as double))
              .reduce(math.max);
          final bottom = regions
              .map((r) => (r['y'] as double) + (r['height'] as double))
              .reduce(math.max);
          measure['source'] = SourceRegion(
            pageId: pageId,
            x: left,
            y: top,
            width: right - left,
            height: bottom - top,
          ).toJson();
        }
      }
    }
    return NotationReviewService.ensureIdentity(
      Score.fromJson(json).copyWith(
        sourcePages: [
          ...score.sourcePages,
          ScoreSourcePage(id: pageId, imageBase64: encoded),
        ],
      ),
    );
  }

  static String? _compress(Uint8List bytes) {
    img.Image? image;
    try {
      image = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (image == null) return null;
    final resized = image.width > 1800 || image.height > 1800
        ? img.copyResize(
            image,
            width: image.width >= image.height ? 1800 : null,
            height: image.height > image.width ? 1800 : null,
          )
        : image;
    return base64Encode(img.encodeJpg(resized, quality: 86));
  }
}

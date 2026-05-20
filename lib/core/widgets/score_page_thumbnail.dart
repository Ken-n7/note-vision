import 'package:flutter/material.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';

class ScorePageThumbnail extends StatelessWidget {
  const ScorePageThumbnail({
    super.key,
    required this.score,
    required this.pageIndex,
    required this.cardWidth,
    this.height,
  });

  final Score score;
  final int pageIndex;
  final double cardWidth;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final layoutPolicy = EditorLayoutPolicy.forPartCount(score.parts.length);
    final thumbnailHeight =
        height ?? cardWidth * layoutPolicy.pageHeight / layoutPolicy.pageWidth;

    if (score.parts.isEmpty || score.parts.first.measures.isEmpty) {
      return _ThumbnailFrame(
        width: cardWidth,
        height: thumbnailHeight,
        child: const Center(
          child: Icon(
            Icons.music_note_rounded,
            color: Color(0xFF9CA3AF),
            size: 24,
          ),
        ),
      );
    }

    final pageStarts = pageStartIndicesForMeasures(
      score.parts.first.measures,
      layoutPolicy: layoutPolicy,
    );
    final clampedPageIndex = pageIndex.clamp(0, pageStarts.length - 1).toInt();
    final firstMeasureIndex = pageStarts[clampedPageIndex];
    final nextMeasureIndex = clampedPageIndex + 1 < pageStarts.length
        ? pageStarts[clampedPageIndex + 1]
        : score.parts.first.measures.length;
    final pageMeasureCount = nextMeasureIndex - firstMeasureIndex;
    final scale = cardWidth / layoutPolicy.pageWidth;

    return _ThumbnailFrame(
      width: cardWidth,
      height: thumbnailHeight,
      child: ClipRect(
        child: IgnorePointer(
          child: Transform.scale(
            alignment: Alignment.topLeft,
            scale: scale,
            child: SizedBox(
              width: layoutPolicy.pageWidth,
              height: layoutPolicy.pageHeight,
              child: ScoreNotationViewer(
                score: score,
                measuresPerRow: layoutPolicy.measuresPerRow,
                minMeasureWidth: layoutPolicy.minMeasureWidth,
                rowHeight: layoutPolicy.rowHeight,
                padding: EdgeInsets.symmetric(
                  horizontal: layoutPolicy.horizontalPadding,
                  vertical: layoutPolicy.verticalPadding,
                ),
                backgroundColor: Colors.white,
                firstMeasureIndex: firstMeasureIndex,
                pageMeasureCount: pageMeasureCount,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbnailFrame extends StatelessWidget {
  const _ThumbnailFrame({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}

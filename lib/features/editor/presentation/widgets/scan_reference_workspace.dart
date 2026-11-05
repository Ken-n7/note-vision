import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';

import 'scan_comparison_view.dart';

/// A photo reference beside the editable paper, following its selection.
class ScanReferenceWorkspace extends StatefulWidget {
  const ScanReferenceWorkspace({
    super.key,
    required this.score,
    required this.partIndex,
    required this.measureIndex,
    required this.symbolIndex,
    required this.notationArea,
    required this.onClose,
  });

  final Score score;
  final int? partIndex, measureIndex, symbolIndex;
  final Widget notationArea;
  final VoidCallback onClose;

  @override
  State<ScanReferenceWorkspace> createState() => _ScanReferenceWorkspaceState();
}

class _ScanReferenceWorkspaceState extends State<ScanReferenceWorkspace> {
  bool _wholePage = false;

  @override
  Widget build(BuildContext context) {
    final part = widget.score.parts.elementAtOrNull(widget.partIndex ?? 0);
    final measure = part?.measures.elementAtOrNull(widget.measureIndex ?? 0);
    final symbol = widget.symbolIndex == null
        ? null
        : measure?.symbols.elementAtOrNull(widget.symbolIndex!);
    final mark = NotationReviewService.sourceOf(symbol);
    final source =
        mark ??
        (measure == null ? null : NotationReviewService.measureSource(measure));
    final page = widget.score.sourcePages
        .where((p) => p.id == source?.pageId)
        .firstOrNull;
    final region = measure == null
        ? null
        : NotationReviewService.measureSource(measure, pageId: source?.pageId);
    final location = measure == null
        ? 'Original scan'
        : 'Original scan · ${part!.name} · Bar ${measure.number}';
    final reference = Material(
      key: const ValueKey('scan-reference-panel'),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, area) {
          final minimumHeight =
              100 + MediaQuery.textScalerOf(context).scale(12);
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _wholePage
                        ? 'Show selected measure'
                        : 'Show full scan page',
                    onPressed: page == null
                        ? null
                        : () => setState(() => _wholePage = !_wholePage),
                    icon: Icon(_wholePage ? Icons.crop : Icons.fullscreen),
                  ),
                  IconButton(
                    tooltip: 'Close original scan',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: page == null || source == null
                      ? const Center(
                          child: Text(
                            'No original scan is attached to this measure.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ScanComparisonView(
                          page: page,
                          region: _wholePage
                              ? SourceRegion(
                                  pageId: page.id,
                                  x: 0,
                                  y: 0,
                                  width: 1,
                                  height: 1,
                                )
                              : region ?? source,
                          highlight: mark ?? (_wholePage ? region : null),
                          semanticsLabel:
                              '$location. '
                              '${mark != null
                                  ? 'The outlined box marks the selected symbol.'
                                  : _wholePage
                                  ? 'The outlined box marks the selected measure.'
                                  : ''}',
                        ),
                ),
              ),
            ],
          );
          return area.maxHeight >= minimumHeight
              ? content
              : SingleChildScrollView(
                  child: SizedBox(height: minimumHeight, child: content),
                );
        },
      ),
    );
    return LayoutBuilder(
      builder: (context, area) {
        if (area.maxWidth >= 600 ||
            (area.maxWidth >= 480 && area.maxHeight < 280)) {
          return Row(
            children: [
              Expanded(child: widget.notationArea),
              const SizedBox(width: 8),
              SizedBox(
                width: (area.maxWidth * .38).clamp(200.0, 320.0),
                child: reference,
              ),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(
              height: math
                  .min(176, math.max(96, area.maxHeight * .4))
                  .clamp(0.0, math.max(0, area.maxHeight - 88))
                  .toDouble(),
              child: reference,
            ),
            const SizedBox(height: 8),
            Expanded(child: widget.notationArea),
          ],
        );
      },
    );
  }
}

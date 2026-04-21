import 'package:flutter/material.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';
import 'detection_overlay.dart';

class ScanImageView extends StatelessWidget {
  final ScanResult result;

  const ScanImageView({super.key, required this.result});

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _surface       = Color(0xFF1A1A1A);
  static const _border        = Color(0xFF2C2C2C);
  // static const _accent        = Color(0xFFD4A96A);
  // static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);
  // static const _success       = Color(0xFF4ADE80);
  // static const _warning       = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    final symbolCount = result.symbols.length;
    final hasDetections = result.hasDetections;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SCAN RESULT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary,
                  letterSpacing: 2.0,
                ),
              ),
              _DetectionBadge(
                count: symbolCount,
                hasDetections: hasDetections,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ── Image dimensions ──────────────────────────────────────────
          Text(
            '${result.preprocessed.width} × ${result.preprocessed.height} px',
            style: const TextStyle(
              fontSize: 12,
              color: _textSecondary,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 16),

          // ── Image viewer ──────────────────────────────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(24),
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: SizedBox(
                    width: result.preprocessed.width.toDouble(),
                    height: result.preprocessed.height.toDouble(),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.memory(
                            result.preprocessed.bytes,
                            fit: BoxFit.fill,
                          ),
                        ),
                        if (hasDetections)
                          Positioned.fill(
                            child: DetectionOverlay(
                              symbols: result.symbols,
                              staffs: result.detection.staffs,
                              imageWidth: result.preprocessed.width,
                              imageHeight: result.preprocessed.height,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Zoom hint ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.pinch_outlined,
                  size: 14,
                  color: _textSecondary.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  'Pinch to zoom · drag to pan',
                  style: TextStyle(
                    fontSize: 11,
                    color: _textSecondary.withValues(alpha: 0.4),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detection badge ──────────────────────────────────────────────────────────

class _DetectionBadge extends StatelessWidget {
  final int count;
  final bool hasDetections;

  const _DetectionBadge({required this.count, required this.hasDetections});

  static const _success = Color(0xFF4ADE80);
  static const _warning = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    final color = hasDetections ? _success : _warning;
    final label = hasDetections
        ? '$count symbol${count == 1 ? '' : 's'} detected'
        : 'No symbols detected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
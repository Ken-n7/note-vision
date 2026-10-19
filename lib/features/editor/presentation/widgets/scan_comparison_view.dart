import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/theme/app_theme.dart';

class ScanComparisonView extends StatefulWidget {
  const ScanComparisonView({
    super.key,
    required this.page,
    required this.region,
    this.highlight,
  });
  final ScoreSourcePage page;
  final SourceRegion region;
  final SourceRegion? highlight;

  @override
  State<ScanComparisonView> createState() => _ScanComparisonViewState();
}

class _ScanComparisonViewState extends State<ScanComparisonView> {
  ui.Image? _image;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ScanComparisonView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    _failed = false;
    final previous = _image;
    _image = null;
    previous?.dispose();
    try {
      final codec = await ui.instantiateImageCodec(
        base64Decode(widget.page.imageBase64),
      );
      ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      if (!mounted || request != _request) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _request++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Original scan of the selected measure. The outlined box marks the selected symbol.',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.white,
          height: 170,
          child: _failed
              ? const Center(
                  child: Text(
                    'This scan image could not be opened.',
                    style: TextStyle(color: Colors.black87),
                  ),
                )
              : _image == null
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _ScanCropPainter(
                        _image!,
                        widget.region,
                        widget.highlight,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ScanCropPainter extends CustomPainter {
  _ScanCropPainter(this.image, this.region, this.highlight);
  final ui.Image image;
  final SourceRegion region;
  final SourceRegion? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = image.width.toDouble(), h = image.height.toDouble();
    final rect = Rect.fromLTWH(
      region.x * w,
      region.y * h,
      math.max(1, region.width * w),
      math.max(1, region.height * h),
    );
    // Include the staff and neighboring notation, not just a tightly cut head.
    final source = Rect.fromLTRB(
      math.max(0, rect.left - w * .035),
      math.max(0, rect.top - h * .025),
      math.min(w, rect.right + w * .035),
      math.min(h, rect.bottom + h * .025),
    );
    if (source.isEmpty) return;
    final scale = math.min(
      size.width / source.width,
      size.height / source.height,
    );
    final dest = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: source.width * scale,
      height: source.height * scale,
    );
    canvas.drawImageRect(
      image,
      source,
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final mark = highlight;
    if (mark == null || mark.pageId != region.pageId) return;
    final box = Rect.fromLTWH(
      dest.left + (mark.x * w - source.left) * scale,
      dest.top + (mark.y * h - source.top) * scale,
      math.max(8, mark.width * w * scale),
      math.max(8, mark.height * h * scale),
    ).inflate(4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_ScanCropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.region != region ||
      oldDelegate.highlight != highlight;
}

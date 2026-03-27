import 'package:flutter/material.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';

import 'notation_layout.dart';
import 'score_notation_painter.dart';

/// Read-only staff notation viewer for a [Score].
///
/// Renders every [Part] in the score as a separate horizontal staff row,
/// each scrollable independently when measures overflow the screen width.
///
/// Tap detection (ticket 43) should be layered via a [GestureDetector]
/// placed on top of this widget — this viewer is intentionally read-only.
///
/// Usage:
/// ```dart
/// ScoreNotationViewer(score: myScore)
/// ScoreNotationViewer(score: myScore, initialPartIndex: 1)
/// ```
class ScoreNotationViewer extends StatefulWidget {
  final Score score;

  /// Which part to display initially when multiple parts exist.
  final int initialPartIndex;

  const ScoreNotationViewer({
    super.key,
    required this.score,
    this.initialPartIndex = 0,
  });

  @override
  State<ScoreNotationViewer> createState() => _ScoreNotationViewerState();
}

class _ScoreNotationViewerState extends State<ScoreNotationViewer> {
  late int _selectedPartIndex;

  static const _bg            = Color(0xFF141414);
  static const _surface       = Color(0xFF1A1A1A);
  static const _border        = Color(0xFF2C2C2C);
  static const _accent        = Color(0xFFD4A96A);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  void initState() {
    super.initState();
    _selectedPartIndex = widget.initialPartIndex
        .clamp(0, (widget.score.parts.length - 1).clamp(0, 999));
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.score;

    if (score.parts.isEmpty) {
      return _buildEmpty('No parts found in this score.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (score.parts.length > 1) _buildPartSelector(score),
        Expanded(
          child: _buildStaffView(score.parts[_selectedPartIndex], score),
        ),
      ],
    );
  }

  Widget _buildPartSelector(Score score) {
    return Container(
      height: 40,
      color: _surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: score.parts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = i == _selectedPartIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedPartIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? _accent.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? _accent : _border,
                  width: 0.5,
                ),
              ),
              child: Text(
                score.parts[i].name,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? _accent : _textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStaffView(Part part, Score score) {
    if (part.measures.isEmpty) {
      return _buildEmpty('This part has no measures.');
    }

    final canvasWidth  = ScoreNotationPainter.computeWidth(part);
    final canvasHeight = NotationLayout.rowHeight;

    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScoreHeader(score, part),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: CustomPaint(
                  size: Size(canvasWidth, canvasHeight),
                  painter: ScoreNotationPainter(
                    score: score,
                    part: part,
                    totalWidth: canvasWidth,
                  ),
                ),
              ),
            ),
          ),
          if (canvasWidth > MediaQuery.of(context).size.width)
            _buildScrollHint(),
        ],
      ),
    );
  }

  Widget _buildScoreHeader(Score score, Part part) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (score.title != 'Untitled') ...[
            Text(
              score.title,
              style: const TextStyle(
                fontFamily: 'MaturaMTScriptCapitals',
                fontSize: 18,
                color: Color(0xFFE8E8E8),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Row(
            children: [
              if (score.composer != 'Unknown composer')
                Text(
                  score.composer,
                  style: const TextStyle(fontSize: 12, color: _textSecondary),
                ),
              if (score.composer != 'Unknown composer' && score.parts.length > 1)
                const Text('  ·  ',
                    style: TextStyle(fontSize: 12, color: _textSecondary)),
              if (score.parts.length > 1)
                Text(
                  part.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: _accent.withOpacity(0.8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: _border),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildScrollHint() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_outlined, size: 13,
              color: _textSecondary.withOpacity(0.4)),
          const SizedBox(width: 6),
          Text(
            'Scroll to see all measures',
            style: TextStyle(
              fontSize: 11,
              color: _textSecondary.withOpacity(0.4),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Container(
      color: _bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_outlined, size: 40,
                color: _textSecondary.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                  fontSize: 13, color: _textSecondary.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }
}
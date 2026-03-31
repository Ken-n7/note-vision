// lib/features/dev/detection_inspector/widgets/di_score_preview.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import '../controller/detection_inspector_controller.dart';
import 'di_section_card.dart';

class DiScorePreview extends StatelessWidget {
  final DetectionInspectorController controller;
  const DiScorePreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final debug = controller.scoreDebugOutput;
    final score = controller.mappingResult?.score;

    return DiSectionCard(
      label: 'SCOREMODEL NOTATION PREVIEW',
      trailing: _CopyButton(text: debug),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScoreNotationViewer(score: score),
          const SizedBox(height: 12),
          _MonoBlock(text: debug),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _copied
              ? const Color(0xFF3DD68C).withValues(alpha: 0.15)
              : const Color(0xFF252A3A),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 11,
              color: _copied
                  ? const Color(0xFF3DD68C)
                  : const Color(0xFF6B7390),
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied' : 'Copy',
              style: TextStyle(
                fontSize: 10,
                color: _copied
                    ? const Color(0xFF3DD68C)
                    : const Color(0xFF6B7390),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonoBlock extends StatelessWidget {
  final String text;
  const _MonoBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Color(0xFFB8C4E0),
          height: 1.65,
        ),
      ),
    );
  }
}
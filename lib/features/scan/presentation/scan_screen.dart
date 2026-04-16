import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/usage_stats_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/preprocessing/data/basic_image_preprocessor.dart';
import 'package:note_vision/features/preprocessing/data/horizontal_projection_staff_detector.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/scan/presentation/scan_viewmodel.dart';
import 'widgets/scan_actions.dart';
import 'widgets/scan_image_view.dart';


class ScanScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const ScanScreen({super.key, required this.imageBytes});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScanViewModel>().run(widget.imageBytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ScanViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Note Vision',
          style: TextStyle(
            fontFamily: 'MaturaMTScriptCapitals',
            fontSize: 22,
            color: AppColors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: switch (vm.state) {
        ScanState.idle         => const SizedBox(),
        ScanState.preprocessing => _PipelineStatus(
            icon: Icons.tune_outlined,
            message: 'Preprocessing image',
            subMessage: 'Cleaning up and preparing your scan…',
          ),
        ScanState.detectingStaves => const _PipelineStatus(
            icon: Icons.grid_4x4_outlined,
            message: 'Detecting staff lines',
            subMessage: 'Finding stave boundaries…',
          ),
        ScanState.detecting    => const _PipelineStatus(
            icon: Icons.image_search_outlined,
            message: 'Detecting symbols',
            subMessage: 'Running the detection model…',
          ),
        ScanState.done         => _buildDone(context, vm),
        ScanState.error        => _buildError(context, vm),
      },
    );
  }

  Widget _buildDone(BuildContext context, ScanViewModel vm) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!vm.result!.hasDetections && context.mounted) {
        _showNoDetectionsBar(context);
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = ResponsiveLayout.horizontalPadding(constraints.maxWidth);
        final isLandscape = constraints.maxWidth > constraints.maxHeight;

        final actions = Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: ScanActions(
            onRedo: () => Navigator.pop(context),
            canContinue: vm.result?.hasDetections ?? false,
            onContinue: () {
              unawaited(UsageStatsService.incrementScans());
              final mappedScore = vm.mappingResult?.score ??
                  const Score(
                    id: 'scan-score',
                    title: 'Scanned Score',
                    composer: 'Unknown',
                    parts: [
                      Part(
                        id: 'P1',
                        name: 'Part 1',
                        measures: [Measure(number: 1, symbols: [])],
                      ),
                    ],
                  );

              Navigator.pushNamed(
                context,
                EditorShellScreen.routeName,
                arguments: EditorShellArgs(
                  score: mappedScore,
                  initialState: EditorState(score: mappedScore),
                ),
              );
            },
          ),
        );

        if (!isLandscape) {
          return Column(
            children: [
              Expanded(child: ScanImageView(result: vm.result!)),
              actions,
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 3, child: ScanImageView(result: vm.result!)),
            Expanded(
              flex: 2,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: actions,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showNoDetectionsBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 16, color: AppColors.accent),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'No symbols detected — try recapturing with better lighting.',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildError(BuildContext context, ScanViewModel vm) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Error icon ──────────────────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 32,
                color: Color(0xFFEF4444),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              vm.errorMessage ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8A8A8A),
                height: 1.6,
              ),
            ),

            const SizedBox(height: 32),

            // ── Go back button ──────────────────────────────────────────
            _TappableButton(
              onPressed: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.background,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pipeline status widget ───────────────────────────────────────────────────

class _PipelineStatus extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subMessage;

  const _PipelineStatus({
    required this.icon,
    required this.message,
    required this.subMessage,
  });

  static const _accent        = Color(0xFFD4A96A);
  static const _surface       = Color(0xFF1A1A1A);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Animated icon container ─────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _accent.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Icon(icon, size: 30, color: _accent),
            ),

            const SizedBox(height: 28),

            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              subMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: _textSecondary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 32),

            // ── Progress indicator ──────────────────────────────────────
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                backgroundColor: _surface,
                valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                borderRadius: BorderRadius.circular(4),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tappable button wrapper ──────────────────────────────────────────────────

class _TappableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;

  const _TappableButton({required this.child, required this.onPressed});

  @override
  State<_TappableButton> createState() => _TappableButtonState();
}

class _TappableButtonState extends State<_TappableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: widget.child,
        ),
      ),
    );
  }
}

// ─── Provider wrapper ─────────────────────────────────────────────────────────

class ScanScreenProvider extends StatelessWidget {
  final Uint8List imageBytes;

  const ScanScreenProvider({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScanViewModel(
        BasicImagePreprocessor(),
        const HorizontalProjectionStaffDetector(),
        TfliteSymbolDetector(),
        mapper: const DetectionToScoreMapperService(),
      ),
      child: ScanScreen(imageBytes: imageBytes),
    );
  }
}

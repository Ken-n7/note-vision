import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/data/tiled_symbol_detector.dart';
import 'package:note_vision/features/preprocessing/data/basic_image_preprocessor.dart';
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
        ScanState.idle => const SizedBox(),
        ScanState.preprocessing => const _PipelineStatus(
            icon: Icons.tune_outlined,
            message: 'Preprocessing image',
            subMessage: 'Cleaning up and preparing your scan…',
            currentState: ScanState.preprocessing,
          ),
        ScanState.staffLineDetection => const _PipelineStatus(
            icon: Icons.horizontal_rule_rounded,
            message: 'Detecting staff lines',
            subMessage: 'Estimating staff baselines and spacing…',
            currentState: ScanState.staffLineDetection,
          ),
        ScanState.staffLineRemoval => const _PipelineStatus(
            icon: Icons.content_cut_rounded,
            message: 'Removing staff lines',
            subMessage: 'Isolating musical symbols from staff strokes…',
            currentState: ScanState.staffLineRemoval,
          ),
        ScanState.symbolDetectionClassification => const _PipelineStatus(
            icon: Icons.image_search_outlined,
            message: 'Detecting symbols in tiles',
            subMessage: 'Scanning zoomed tiles and classifying symbols…',
            currentState: ScanState.symbolDetectionClassification,
          ),
        ScanState.symbolToStaffAssignment => const _PipelineStatus(
            icon: Icons.call_split_rounded,
            message: 'Assigning symbols to staffs',
            subMessage: 'Linking each symbol to its staff region…',
            currentState: ScanState.symbolToStaffAssignment,
          ),
        ScanState.pitchReconstruction => const _PipelineStatus(
            icon: Icons.music_note_rounded,
            message: 'Reconstructing pitch',
            subMessage: 'Mapping noteheads to lines/spaces…',
            currentState: ScanState.pitchReconstruction,
          ),
        ScanState.rhythmReconstruction => const _PipelineStatus(
            icon: Icons.timelapse_rounded,
            message: 'Reconstructing rhythm',
            subMessage: 'Associating stems/flags/beams into durations…',
            currentState: ScanState.rhythmReconstruction,
          ),
        ScanState.measureGrouping => const _PipelineStatus(
            icon: Icons.view_week_outlined,
            message: 'Grouping measures',
            subMessage: 'Using barlines to segment musical events…',
            currentState: ScanState.measureGrouping,
          ),
        ScanState.scoreAssembly => const _PipelineStatus(
            icon: Icons.library_music_outlined,
            message: 'Assembling score model',
            subMessage: 'Building the final score structure…',
            currentState: ScanState.scoreAssembly,
          ),
        ScanState.done => _buildDone(context, vm),
        ScanState.error => _buildError(context, vm),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _PipelineStagesTimeline(currentState: ScanState.done),
              ),
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
  final ScanState currentState;

  const _PipelineStatus({
    required this.icon,
    required this.message,
    required this.subMessage,
    required this.currentState,
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
            const SizedBox(height: 20),
            _PipelineStagesTimeline(currentState: currentState),
          ],
        ),
      ),
    );
  }
}

class _PipelineStageItem {
  final ScanState state;
  final String title;
  final String hint;

  const _PipelineStageItem({
    required this.state,
    required this.title,
    required this.hint,
  });
}

class _PipelineStagesTimeline extends StatelessWidget {
  final ScanState currentState;

  const _PipelineStagesTimeline({required this.currentState});

  static const _stages = [
    _PipelineStageItem(
      state: ScanState.preprocessing,
      title: '1. Preprocessing',
      hint: 'Grayscale, straighten, denoise, binarize prep',
    ),
    _PipelineStageItem(
      state: ScanState.staffLineDetection,
      title: '2. Staff Line Detection',
      hint: 'Find line positions, spacing, staff bounds',
    ),
    _PipelineStageItem(
      state: ScanState.staffLineRemoval,
      title: '3. Staff Line Removal',
      hint: 'Suppress staff strokes while preserving symbols',
    ),
    _PipelineStageItem(
      state: ScanState.symbolDetectionClassification,
      title: '4. Symbol Detection / Classification',
      hint: 'Run detector on tiles and classify note/rest/clef',
    ),
    _PipelineStageItem(
      state: ScanState.symbolToStaffAssignment,
      title: '5. Symbol to Staff Assignment',
      hint: 'Attach each symbol to the best staff region',
    ),
    _PipelineStageItem(
      state: ScanState.pitchReconstruction,
      title: '6. Pitch Reconstruction',
      hint: 'Map notehead Y to nearest staff line/space',
    ),
    _PipelineStageItem(
      state: ScanState.rhythmReconstruction,
      title: '7. Rhythm Reconstruction',
      hint: 'Use stems/flags/beams to infer durations',
    ),
    _PipelineStageItem(
      state: ScanState.measureGrouping,
      title: '8. Measure Grouping',
      hint: 'Use barlines to segment symbols into measures',
    ),
    _PipelineStageItem(
      state: ScanState.scoreAssembly,
      title: '9. Score Assembly',
      hint: 'Build final score structure and signatures',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _stages.indexWhere((s) => s.state == currentState);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151820),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PIPELINE DEBUG (temporary)',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF8A8FA3),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(_stages.length, (index) {
            final item = _stages[index];
            final isActive = currentState == item.state;
            final isDone = currentState == ScanState.done || (currentIndex != -1 && index < currentIndex);

            final color = isActive
                ? const Color(0xFFD4A96A)
                : (isDone ? const Color(0xFF4ADE80) : const Color(0xFF6B7280));

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isDone ? Icons.check_circle : (isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        Text(
                          item.hint,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8A8A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
        TiledSymbolDetector(
          TfliteSymbolDetector(),
          gridColumns: 2,
          gridRows: 2,
          overlapFraction: 0.3,
        ),
      ),
      child: ScanScreen(imageBytes: imageBytes),
    );
  }
}

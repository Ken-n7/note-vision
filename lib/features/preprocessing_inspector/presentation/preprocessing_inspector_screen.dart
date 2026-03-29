import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../core/theme/app_theme.dart';
import '../../preprocessing/data/basic_image_preprocessor.dart';
import '../../preprocessing/domain/image_preprocessor.dart';
import '../../preprocessing/domain/preprocessed_result.dart';
import '../data/dev_staff_line_detector.dart';
import '../data/experimental_image_preprocessor.dart';

enum _PreprocessorChoice { baseline, experimental }

class PreprocessingInspectorScreen extends StatefulWidget {
  const PreprocessingInspectorScreen({super.key});

  @override
  State<PreprocessingInspectorScreen> createState() =>
      _PreprocessingInspectorScreenState();
}

class _PreprocessingInspectorScreenState
    extends State<PreprocessingInspectorScreen> {
  static const _bg = Color(0xFF0F1117);
  static const _surface = Color(0xFF181C27);
  static const _border = Color(0xFF252A3A);
  static const _accent = Color(0xFF4F8EF7);
  static const _textPri = Color(0xFFE8ECF4);
  static const _textSec = Color(0xFF6B7390);

  final ImagePreprocessor _baseline = BasicImagePreprocessor();
  final ImagePreprocessor _experimental = const ExperimentalImagePreprocessor();
  final DevStaffLineDetector _staffLineDetector = const DevStaffLineDetector();

  _PreprocessorChoice _choice = _PreprocessorChoice.experimental;
  bool _isRunning = false;
  String? _error;

  String? _fileName;
  Uint8List? _inputBytes;
  img.Image? _decodedInput;

  PreprocessedResult? _output;
  DevStaffLineDetectionResult? _staffLineResult;
  Duration? _elapsed;
  Duration? _stage2Elapsed;

  Future<void> _pickImageAndRun() async {
    setState(() {
      _isRunning = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        withData: true,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );

      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _isRunning = false);
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _isRunning = false;
          _error = 'Unable to read file bytes.';
        });
        return;
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() {
          _isRunning = false;
          _error = 'Unsupported or corrupted image file.';
        });
        return;
      }

      final preprocessor = _choice == _PreprocessorChoice.baseline
          ? _baseline
          : _experimental;

      final sw = Stopwatch()..start();
      final output = await preprocessor.preprocess(bytes);
      sw.stop();

      final swStage2 = Stopwatch()..start();
      final staffLines = await _staffLineDetector.detect(output.bytes);
      swStage2.stop();

      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _inputBytes = bytes;
        _decodedInput = decoded;
        _output = output;
        _staffLineResult = staffLines;
        _elapsed = sw.elapsed;
        _stage2Elapsed = swStage2.elapsed;
        _isRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _error = 'Preprocessing failed: $e';
      });
    }
  }

  Future<void> _rerun() async {
    final input = _inputBytes;
    if (input == null) return;

    setState(() {
      _isRunning = true;
      _error = null;
    });

    try {
      final preprocessor = _choice == _PreprocessorChoice.baseline
          ? _baseline
          : _experimental;

      final sw = Stopwatch()..start();
      final output = await preprocessor.preprocess(input);
      sw.stop();

      final swStage2 = Stopwatch()..start();
      final staffLines = await _staffLineDetector.detect(output.bytes);
      swStage2.stop();

      if (!mounted) return;
      setState(() {
        _output = output;
        _staffLineResult = staffLines;
        _elapsed = sw.elapsed;
        _stage2Elapsed = swStage2.elapsed;
        _isRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _error = 'Preprocessing failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: _textPri),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Preprocessing Inspector',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _textPri,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildControlPanel(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _buildError(_error!),
            ],
            const SizedBox(height: 14),
            _buildStageCard(
              title: 'Stage 0 · Input',
              child: _buildInputPreview(),
            ),
            const SizedBox(height: 12),
            _buildStageCard(
              title: 'Stage 1 · Preprocessing Output',
              child: _buildOutputPreview(),
            ),
            const SizedBox(height: 12),
            _buildStageCard(
              title: 'Stage 2 · Staff Line Detection (DEV heuristic)',
              child: _buildStaffLineStage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DEV PIPELINE AREA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _textSec,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This inspector is isolated from the production scan flow.',
            style: TextStyle(fontSize: 13, color: _textPri),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Experimental Preprocessor'),
                selected: _choice == _PreprocessorChoice.experimental,
                onSelected: _isRunning
                    ? null
                    : (_) {
                        setState(() {
                          _choice = _PreprocessorChoice.experimental;
                        });
                        _rerun();
                      },
              ),
              ChoiceChip(
                label: const Text('Baseline Preprocessor'),
                selected: _choice == _PreprocessorChoice.baseline,
                onSelected: _isRunning
                    ? null
                    : (_) {
                        setState(() {
                          _choice = _PreprocessorChoice.baseline;
                        });
                        _rerun();
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isRunning ? null : _pickImageAndRun,
              icon: _isRunning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file, size: 16),
              label: Text(_isRunning ? 'Running...' : 'Load Image + Run Stage 1'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Loaded file: $_fileName',
              style: const TextStyle(fontSize: 12, color: _textSec),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputPreview() {
    final decoded = _decodedInput;
    final bytes = _inputBytes;
    if (decoded == null || bytes == null) {
      return const _EmptyState(
        icon: Icons.image_not_supported_outlined,
        message: 'No input loaded yet.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
        const SizedBox(height: 10),
        Text(
          'Original size: ${decoded.width} × ${decoded.height}',
          style: const TextStyle(fontSize: 12, color: _textSec),
        ),
      ],
    );
  }

  Widget _buildOutputPreview() {
    final output = _output;
    if (output == null) {
      return const _EmptyState(
        icon: Icons.tune_outlined,
        message: 'Run preprocessing to inspect this stage.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(output.bytes, fit: BoxFit.contain),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            _metaChip('Output', '${output.width}×${output.height}'),
            _metaChip('Scale', output.scale.toStringAsFixed(4)),
            _metaChip('padX', output.padX.toString()),
            _metaChip('padY', output.padY.toString()),
            if (_elapsed != null)
              _metaChip('Runtime', '${_elapsed!.inMilliseconds} ms'),
            _metaChip(
              'Mode',
              _choice == _PreprocessorChoice.experimental
                  ? 'Experimental'
                  : 'Baseline',
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildStaffLineStage() {
    final output = _output;
    final stage = _staffLineResult;
    if (output == null || stage == null) {
      return const _EmptyState(
        icon: Icons.horizontal_rule_outlined,
        message: 'Run stage 1 first to enable staff-line detection.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            foregroundPainter: _StaffLineOverlayPainter(lines: stage.lines),
            child: Image.memory(output.bytes, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            _metaChip('Detected lines', stage.lines.length.toString()),
            _metaChip('Dark rows', stage.darkRows.toString()),
            _metaChip('Threshold', stage.minDarkRatio.toStringAsFixed(2)),
            if (_stage2Elapsed != null)
              _metaChip('Runtime', '${_stage2Elapsed!.inMilliseconds} ms'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          stage.hasLines
              ? 'Top lines: ${stage.lines.take(8).map((l) => l.y.toStringAsFixed(1)).join(', ')}'
              : 'No strong horizontal staff candidates found.',
          style: const TextStyle(fontSize: 12, color: _textSec, height: 1.4),
        ),
      ],
    );
  }

  Widget _metaChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, color: _textSec),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
      ),
    );
  }

  Widget _buildStageCard({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'DEV',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: _accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: _textPri,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _PreprocessingInspectorScreenState._border),
      ),
      child: Column(
        children: [
          Icon(icon, color: _PreprocessingInspectorScreenState._textSec),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: _PreprocessingInspectorScreenState._textSec,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}


class _StaffLineOverlayPainter extends CustomPainter {
  const _StaffLineOverlayPainter({required this.lines});

  final List<DevStaffLine> lines;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || size.height <= 0) return;

    final paint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.85)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final line in lines) {
      final y = line.y.clamp(0, 415) / 416 * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StaffLineOverlayPainter oldDelegate) {
    return oldDelegate.lines != lines;
  }
}

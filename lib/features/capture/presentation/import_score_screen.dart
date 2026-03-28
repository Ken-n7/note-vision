import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/musicXML/musicxml_parser_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/musicXML/musicxml_validator_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/capture/presentation/capture_screen.dart';

class ImportScoreScreen extends StatefulWidget {
  const ImportScoreScreen({super.key});

  @override
  State<ImportScoreScreen> createState() => _ImportScoreScreenState();
}

class _ImportScoreScreenState extends State<ImportScoreScreen> {
  static const _xmlParser = MusicXmlParserService();
  static const _xmlConverter = MusicXmlScoreConverter();
  static const _xmlValidator = MusicXmlValidatorService();

  static const _bg = Color(0xFF0D0D0D);
  static const _surface = Color(0xFF1A1A1A);
  static const _border = Color(0xFF2C2C2C);
  static const _accent = Color(0xFFD4A96A);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  bool _isLoading = false;
  Score? _importedScore;
  String? _selectedFileName;
  List<String> _errors = const [];
  List<String> _warnings = const [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: _textPrimary),
          onPressed: _goToCollection,
        ),
        title: const Text(
          'Note Vision',
          style: TextStyle(
            fontFamily: 'MaturaMTScriptCapitals',
            fontSize: 22,
            color: _textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IMPORT SCORE FILE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Import a MusicXML file, preview it, then continue to the editor.',
              style: TextStyle(
                fontSize: 14,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(child: _buildPreviewArea()),
            const SizedBox(height: 14),
            if (_warnings.isNotEmpty) ...[
              _buildMessageCard(
                title: 'Warnings',
                icon: Icons.info_outline,
                color: _accent,
                messages: _warnings,
              ),
              const SizedBox(height: 10),
            ],
            if (_errors.isNotEmpty) ...[
              _buildMessageCard(
                title: 'Import Issues',
                icon: Icons.error_outline,
                color: const Color(0xFFFF6B6B),
                messages: _errors,
              ),
              const SizedBox(height: 10),
            ],
            _buildActionRow(),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildPreviewArea() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: _importedScore != null
            ? ScoreNotationViewer(
                score: _importedScore,
                backgroundColor: const Color(0xFFF9FAFB),
              )
            : _buildEmptyPreview(),
      ),
    );
  }

  Widget _buildEmptyPreview() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _border, width: 1.5),
          ),
          child: const Icon(
            Icons.library_music_outlined,
            color: _textSecondary,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No score imported',
          style: TextStyle(
            fontSize: 14,
            color: _textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _selectedFileName == null
              ? 'Import MusicXML or JSON (DEV) below'
              : 'Selected: $_selectedFileName',
          style: TextStyle(
            fontSize: 12,
            color: _textSecondary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> messages,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $message',
                style: const TextStyle(
                  fontSize: 12,
                  color: _textPrimary,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    if (_importedScore != null) {
      return Column(
        children: [
          _buildContinueButton(),
          const SizedBox(height: 10),
          _TappableButton(
            onPressed: _cancelSelection,
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        _buildPrimaryButton(
          label: 'Import MusicXML',
          icon: Icons.library_music_outlined,
          onPressed: _isLoading ? null : _importMusicXml,
        ),
        const SizedBox(width: 12),
        _buildGhostButton(
          label: 'Import JSON (DEV)',
          icon: Icons.developer_mode_outlined,
          onPressed: _isLoading ? null : _importJson,
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: _TappableButton(
        onPressed: onPressed,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: onPressed == null ? _border : _textPrimary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _bg),
                )
              else
                Icon(icon, size: 18, color: _bg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onPressed == null ? _textSecondary : _bg,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGhostButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: _TappableButton(
        onPressed: onPressed,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _textSecondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: _textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return _TappableButton(
      onPressed: _continueToEditor,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: _textPrimary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Continue',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _bg,
                letterSpacing: 0.4,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: 18, color: _bg),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _BottomNavItem(
                icon: Icons.camera_alt_outlined,
                label: 'Scan',
                isSelected: false,
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const CaptureScreen()),
                  );
                },
              ),
              _BottomNavItem(
                icon: Icons.upload_file_outlined,
                label: 'Import',
                isSelected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importMusicXml() async {
    setState(() {
      _isLoading = true;
      _errors = const [];
      _warnings = const [];
      _importedScore = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const ['xml', 'musicxml'],
    );

    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _isLoading = false;
        _selectedFileName = file.name;
        _errors = const ['Unable to read file bytes.'];
      });
      return;
    }

    try {
      final parsed = _xmlParser.parse(utf8.decode(bytes));
      if (!parsed.success || parsed.document == null) {
        setState(() {
          _selectedFileName = file.name;
          _errors = [parsed.errorMessage ?? 'Invalid MusicXML content.'];
          _warnings = const [];
          _importedScore = null;
          _isLoading = false;
        });
        return;
      }

      final validation = _xmlValidator.validate(parsed.document!);
      if (!validation.isValid) {
        setState(() {
          _selectedFileName = file.name;
          _errors = validation.validationErrors;
          _warnings = validation.warnings;
          _importedScore = null;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _selectedFileName = file.name;
        _errors = const [];
        _warnings = validation.warnings;
        _importedScore = _xmlConverter.convert(parsed.document!);
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _selectedFileName = file.name;
        _errors = const ['Could not import MusicXML file.'];
        _warnings = const [];
        _importedScore = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _importJson() async {
    setState(() {
      _errors = const [];
      _warnings = const [];
      _importedScore = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const ['json'],
    );

    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final data = file.bytes;

    if (data == null) {
      setState(() {
        _selectedFileName = file.name;
        _errors = const ['Unable to read JSON file.'];
      });
      return;
    }

    try {
      final score = _scoreFromJson(utf8.decode(data));
      setState(() {
        _selectedFileName = file.name;
        _importedScore = score;
        _errors = const [];
        _warnings = const ['JSON import is a temporary developer feature.'];
      });
    } catch (_) {
      setState(() {
        _selectedFileName = file.name;
        _importedScore = null;
        _errors = const ['Invalid score JSON format.'];
        _warnings = const [];
      });
    }
  }

  void _cancelSelection() {
    setState(() {
      _importedScore = null;
      _errors = const [];
      _warnings = const [];
      _selectedFileName = null;
    });
  }

  void _continueToEditor() {
    final score = _importedScore;
    if (score == null) return;

    Navigator.pushNamed(
      context,
      EditorShellScreen.routeName,
      arguments: EditorShellArgs(
        score: score,
        initialState: EditorState(score: score),
      ),
    );
  }

  void _goToCollection() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CollectionScreen()),
      (route) => false,
    );
  }

  Score _scoreFromJson(String content) {
    final root = jsonDecode(content);
    if (root is! Map) {
      throw const FormatException('JSON root must be an object');
    }
    final rootMap = Map<String, dynamic>.from(root);

    final partMaps = (rootMap['parts'] as List?)
            ?.whereType<Map>()
            .map((part) => Map<String, dynamic>.from(part))
            .toList() ??
        [];
    if (partMaps.isEmpty) {
      throw const FormatException('Score JSON must include parts');
    }

    final parts = partMaps.map((part) {
      final measureMaps = (part['measures'] as List?)
              ?.whereType<Map>()
              .map((measure) => Map<String, dynamic>.from(measure))
              .toList() ??
          [];
      return Part(
        id: (part['id']?.toString().isNotEmpty ?? false)
            ? part['id'].toString()
            : 'P1',
        name: part['name']?.toString() ?? 'Part 1',
        measures: measureMaps.map(_measureFromJson).toList(),
      );
    }).toList();

    return Score(
      id: rootMap['id']?.toString() ?? 'imported-score',
      title: rootMap['title']?.toString() ?? 'Imported Score',
      composer: rootMap['composer']?.toString() ?? 'Unknown',
      parts: parts,
    );
  }

  Measure _measureFromJson(Map<String, dynamic> measure) {
    final symbolMaps = (measure['symbols'] as List?)
            ?.whereType<Map>()
            .map((symbol) => Map<String, dynamic>.from(symbol))
            .toList() ??
        [];
    return Measure(
      number: (measure['number'] as num?)?.toInt() ?? 1,
      symbols: symbolMaps.map(_symbolFromJson).toList(),
    );
  }

  ScoreSymbol _symbolFromJson(Map<String, dynamic> symbol) {
    final type = symbol['type']?.toString().toLowerCase();
    if (type == 'rest') {
      return Rest(
        duration: (symbol['duration'] as num?)?.toInt() ?? 1,
        type: symbol['restType']?.toString() ??
            symbol['noteType']?.toString() ??
            'quarter',
        voice: (symbol['voice'] as num?)?.toInt(),
        staff: (symbol['staff'] as num?)?.toInt(),
      );
    }

    final pitch = symbol['pitch']?.toString().toUpperCase() ?? 'C4';
    final match = RegExp(r'^([A-G])([#B]*)(\d)$').firstMatch(pitch);
    final step = match?.group(1) ?? symbol['step']?.toString().toUpperCase() ?? 'C';
    final accidental = match?.group(2) ?? '';
    final alter = accidental.isEmpty
        ? (symbol['alter'] as num?)?.toInt()
        : accidental.replaceAll('B', 'b').split('').fold<int>(
              0,
              (value, c) => value + (c == '#' ? 1 : c == 'b' ? -1 : 0),
            );
    final octave = int.tryParse(match?.group(3) ?? '') ??
        (symbol['octave'] as num?)?.toInt() ??
        4;

    return Note(
      step: step,
      octave: octave,
      alter: alter,
      duration: (symbol['duration'] as num?)?.toInt() ?? 1,
      type: symbol['noteType']?.toString() ??
          symbol['typeName']?.toString() ??
          'quarter',
      voice: (symbol['voice'] as num?)?.toInt(),
      staff: (symbol['staff'] as num?)?.toInt(),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  static const _accent = Color(0xFFD4A96A);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? _accent : _textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? _accent : _textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TappableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const _TappableButton({required this.child, required this.onPressed});

  @override
  State<_TappableButton> createState() => _TappableButtonState();
}

class _TappableButtonState extends State<_TappableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onPressed == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onPressed!();
            },
      onTapCancel: widget.onPressed == null ? null : () => setState(() => _pressed = false),
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

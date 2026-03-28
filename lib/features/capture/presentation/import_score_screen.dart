import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/musicXML/musicxml_parser_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/musicXML/musicxml_validator_service.dart';

class ImportScoreScreen extends StatefulWidget {
  const ImportScoreScreen({super.key});

  @override
  State<ImportScoreScreen> createState() => _ImportScoreScreenState();
}

class _ImportScoreScreenState extends State<ImportScoreScreen> {
  static const _xmlParser = MusicXmlParserService();
  static const _xmlConverter = MusicXmlScoreConverter();
  static const _xmlValidator = MusicXmlValidatorService();

  Score? _importedScore;
  String? _selectedFileName;
  List<String> _errors = const [];
  List<String> _warnings = const [];
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Import Score',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImportActions(),
              const SizedBox(height: 14),
              if (_selectedFileName != null)
                Text(
                  'Selected: $_selectedFileName',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              if (_warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildMessageCard(
                  title: 'Warnings',
                  color: Colors.amber,
                  messages: _warnings,
                ),
              ],
              if (_errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildMessageCard(
                  title: 'Import issues',
                  color: const Color(0xFFEF4444),
                  messages: _errors,
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _importedScore == null
                      ? const Center(
                          child: Text(
                            'Import a MusicXML file to preview notation.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ScoreNotationViewer(
                          score: _importedScore,
                          backgroundColor: const Color(0xFFF9FAFB),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: (_isLoading || _importedScore == null)
                    ? null
                    : _continueToEditor,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.background,
                  disabledBackgroundColor: AppColors.border,
                  disabledForegroundColor: AppColors.textSecondary,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _importMusicXml,
            icon: _isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.music_note_outlined),
            label: const Text('Import MusicXML'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _importJson,
            icon: const Icon(Icons.developer_mode_outlined),
            label: const Text('Import JSON (DEV)'),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard({
    required String title,
    required Color color,
    required List<String> messages,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $message',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
        ],
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
    final data = file.bytes;
    if (data == null) {
      setState(() {
        _isLoading = false;
        _selectedFileName = file.name;
        _errors = const ['Unable to read file bytes.'];
      });
      return;
    }

    try {
      final xmlContent = utf8.decode(data);
      final parsed = _xmlParser.parse(xmlContent);
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

      final score = _xmlConverter.convert(parsed.document!);
      setState(() {
        _selectedFileName = file.name;
        _errors = const [];
        _warnings = validation.warnings;
        _importedScore = score;
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
}

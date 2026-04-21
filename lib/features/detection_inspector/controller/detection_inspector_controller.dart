// lib/features/dev/detection_inspector/controller/detection_inspector_controller.dart

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';

import '../data/mock_detection_data.dart';
import '../model/mapping_pipeline_state.dart';

enum InspectorStatus { idle, loaded, mapped, error }

class MockCase {
  final String label;
  final String description;
  final String json;

  const MockCase({
    required this.label,
    required this.description,
    required this.json,
  });
}

class DetectionInspectorController extends ChangeNotifier {
  static const _cases = [
    MockCase(
      label: 'Case 1 — Typical',
      description: '1 staff · 2 measures · notes + rests',
      json: kMockDetectionCase1,
    ),
    MockCase(
      label: 'Case 2 — No Staffs',
      description: 'Edge case: no staffs, triggers warnings',
      json: kMockDetectionCase2,
    ),
    MockCase(
      label: 'Case 3 — Multi-Measure',
      description: '1 staff · 3 measures · rich symbols',
      json: kMockDetectionCase3,
    ),
  ];

  static List<MockCase> get availableCases => _cases;

  final _mapper = const DetectionToScoreMapperService();

  InspectorStatus _status = InspectorStatus.idle;
  InspectorStatus get status => _status;

  MockCase? _loadedCase;
  MockCase? get loadedCase => _loadedCase;

  /// Non-null when a file was picked from disk (not a preset case).
  String? _loadedFileName;
  String? get loadedFileName => _loadedFileName;

  String? _loadedRawJson;

  DetectionResult? _detection;
  DetectionResult? get detection => _detection;

  MappingResult? _mappingResult;
  MappingResult? get mappingResult => _mappingResult;

  MappingPipelineState? _pipelineState;
  MappingPipelineState? get pipelineState => _pipelineState;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isRunningMapping = false;
  bool get isRunningMapping => _isRunningMapping;

  bool _isLoadingFile = false;
  bool get isLoadingFile => _isLoadingFile;

  // ── Detection summary ──────────────────────────────────────────────────────

  int get staffCount => _detection?.staffs.length ?? 0;
  int get barlineCount => _detection?.barlines.length ?? 0;
  int get symbolCount => _detection?.symbols.length ?? 0;

  // ── Mapping summary ────────────────────────────────────────────────────────

  int get measuresCreated {
    final score = _mappingResult?.score;
    if (score == null) return 0;
    return score.parts.fold(0, (sum, p) => sum + p.measures.length);
  }

  int get notesCreated {
    final score = _mappingResult?.score;
    if (score == null) return 0;
    return score.parts.fold(
      0,
      (sum, p) => sum + p.measures.fold(0, (s, m) => s + m.notes.length),
    );
  }

  int get restsCreated {
    final score = _mappingResult?.score;
    if (score == null) return 0;
    return score.parts.fold(
      0,
      (sum, p) => sum + p.measures.fold(0, (s, m) => s + m.rests.length),
    );
  }

  List<String> get warnings => _mappingResult?.warnings ?? [];
  List<String> get errors => _mappingResult?.errors ?? [];

  // ── Raw JSON ───────────────────────────────────────────────────────────────

  String? get rawJsonPretty {
    final source = _loadedCase?.json ?? _loadedRawJson;
    if (source == null) return null;
    try {
      final decoded = jsonDecode(source);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return source;
    }
  }

  // ── Score debug output ─────────────────────────────────────────────────────

  String get scoreDebugOutput {
    final score = _mappingResult?.score;
    if (score == null) return '—';

    final sb = StringBuffer();
    sb.writeln('Score id: ${score.id}');
    sb.writeln('Parts: ${score.parts.length}');
    for (final part in score.parts) {
      sb.writeln(
          '  Part "${part.name}" (${part.id}): ${part.measures.length} measure(s)');
      for (final m in part.measures) {
        final clefStr = m.clef != null ? '${m.clef!.sign}-clef' : 'no clef';
        final timeSigStr = m.timeSignature != null
            ? '${m.timeSignature!.beats}/${m.timeSignature!.beatType}'
            : 'no time sig';
        sb.writeln(
            '    Measure ${m.number}: $clefStr, $timeSigStr, ${m.symbols.length} symbol(s)');
        for (final sym in m.symbols) {
          sb.writeln('      • $sym');
        }
      }
    }

    final cs = _mappingResult?.confidenceSummary;
    if (cs != null) {
      sb.writeln('\nConfidence Summary:');
      sb.writeln('  Input symbols:  ${cs.inputSymbolCount}');
      sb.writeln('  Mapped:         ${cs.mappedSymbolCount}');
      sb.writeln('  Dropped:        ${cs.droppedSymbolCount}');
      if (cs.averageDetectionConfidence != null) {
        sb.writeln(
            '  Avg confidence: ${(cs.averageDetectionConfidence! * 100).toStringAsFixed(1)}%');
      }
    }

    return sb.toString();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void loadMockCase(MockCase mockCase) {
    try {
      final json = jsonDecode(mockCase.json) as Map<String, dynamic>;
      _detection = DetectionResult.fromJson(json);
      _loadedCase = mockCase;
      _loadedFileName = null;
      _loadedRawJson = null;
      _mappingResult = null;
      _pipelineState = null;
      _errorMessage = null;
      _status = InspectorStatus.loaded;
    } catch (e) {
      _errorMessage = 'Failed to parse mock JSON: $e';
      _status = InspectorStatus.error;
    }
    notifyListeners();
  }

  /// Opens the system file picker filtered to .json only.
  /// Validates extension, parses JSON, and loads into DetectionResult.
  Future<void> loadFromFile() async {
    _isLoadingFile = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      // User cancelled — silently return, don't change state
      if (result == null || result.files.isEmpty) {
        _isLoadingFile = false;
        notifyListeners();
        return;
      }

      final file = result.files.single;

      // Guard: double-check extension — some platforms ignore the filter
      if (!file.name.toLowerCase().endsWith('.json')) {
        _errorMessage =
            '"${file.name}" is not a JSON file.\nOnly .json files are accepted.';
        _status = InspectorStatus.error;
        _isLoadingFile = false;
        notifyListeners();
        return;
      }

      // Read raw content
      final String jsonString;
      if (file.bytes != null) {
        jsonString = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        jsonString = await File(file.path!).readAsString();
      } else {
        _errorMessage = 'Could not read "${file.name}". No content available.';
        _status = InspectorStatus.error;
        _isLoadingFile = false;
        notifyListeners();
        return;
      }

      // Validate it parses as JSON
      final dynamic decoded;
      try {
        decoded = jsonDecode(jsonString);
      } on FormatException {
        _errorMessage =
            '"${file.name}" contains invalid JSON.\nPlease check the file and try again.';
        _status = InspectorStatus.error;
        _isLoadingFile = false;
        notifyListeners();
        return;
      }

      // Must be a JSON object, not an array or primitive
      if (decoded is! Map) {
        _errorMessage =
            '"${file.name}" must be a JSON object { … }.\nArrays and primitives are not valid DetectionResult format.';
        _status = InspectorStatus.error;
        _isLoadingFile = false;
        notifyListeners();
        return;
      }

      // Parse into DetectionResult
      _detection = DetectionResult.fromJson(Map<String, dynamic>.from(decoded));
      _loadedCase = null;
      _loadedFileName = file.name;
      _loadedRawJson = jsonString;
      _mappingResult = null;
      _pipelineState = null;
      _errorMessage = null;
      _status = InspectorStatus.loaded;
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      _status = InspectorStatus.error;
    } finally {
      _isLoadingFile = false;
      notifyListeners();
    }
  }

  Future<void> runMapping() async {
    if (_detection == null) return;
    _isRunningMapping = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      _pipelineState = _mapper.mapWithPipeline(_detection!);
      _mappingResult = _pipelineState!.result;
      _status = InspectorStatus.mapped;
    } catch (e) {
      _errorMessage = 'Mapping failed: $e';
      _status = InspectorStatus.error;
    } finally {
      _isRunningMapping = false;
      notifyListeners();
    }
  }

  void reset() {
    _status = InspectorStatus.idle;
    _loadedCase = null;
    _loadedFileName = null;
    _loadedRawJson = null;
    _detection = null;
    _mappingResult = null;
    _pipelineState = null;
    _errorMessage = null;
    _isRunningMapping = false;
    _isLoadingFile = false;
    notifyListeners();
  }
}
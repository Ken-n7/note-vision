import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../features/musicXML/musicxml_import_exception.dart';
import '../../features/musicXML/musicxml_importer.dart';
import '../../features/musicXML/musicxml_import_result.dart';
import '../../features/musicXML/musicxml_parse_result.dart';
import '../../features/musicXML/musicxml_score_converter.dart';
import '../../core/models/score.dart';


// ─── Data model for parsed metadata ──────────────────────────────────────────

class _ParsedMetadata {
  final String rootTag;
  final String? title;
  final String? composer;
  final int partCount;
  final int measureCount;
  final int noteCount;
  final List<String> validationErrors;
  final List<String> warnings;

  const _ParsedMetadata({
    required this.rootTag,
    required this.title,
    required this.composer,
    required this.partCount,
    required this.measureCount,
    required this.noteCount,
    this.validationErrors = const [],
    this.warnings = const [],
  });
}

// ─── Screen state ─────────────────────────────────────────────────────────────

enum _ScreenState { empty, success, parseError, validationError }

class _InspectorState {
  final _ScreenState status;
  final String? fileName;
  final _ParsedMetadata? metadata;
  final String? errorMessage;
  final String? rawXml;
  final Score? score;

  const _InspectorState._({
    required this.status,
    this.fileName,
    this.metadata,
    this.errorMessage,
    this.rawXml,
    this.score,
  });

  factory _InspectorState.empty() =>
      const _InspectorState._(status: _ScreenState.empty);

  factory _InspectorState.success({
    required String fileName,
    required _ParsedMetadata metadata,
    required String rawXml,
    Score? score,
  }) =>
      _InspectorState._(
        status: _ScreenState.success,
        fileName: fileName,
        metadata: metadata,
        rawXml: rawXml,
        score: score,
      );

  /// Parse failed before we could even read a root tag.
  factory _InspectorState.parseError({
    required String fileName,
    required String errorMessage,
  }) =>
      _InspectorState._(
        status: _ScreenState.parseError,
        fileName: fileName,
        errorMessage: errorMessage,
      );

  /// XML parsed but failed MusicXML structural validation.
  factory _InspectorState.validationError({
    required String fileName,
    required _ParsedMetadata metadata,
    required String rawXml,
    required String errorMessage,
  }) =>
      _InspectorState._(
        status: _ScreenState.validationError,
        fileName: fileName,
        metadata: metadata,
        rawXml: rawXml,
        errorMessage: errorMessage,
      );
}

// ─── Main screen ─────────────────────────────────────────────────────────────

class MusicXmlInspectorScreen extends StatefulWidget {
  const MusicXmlInspectorScreen({super.key});

  @override
  State<MusicXmlInspectorScreen> createState() =>
      _MusicXmlInspectorScreenState();
}

class _MusicXmlInspectorScreenState extends State<MusicXmlInspectorScreen> {
  final _importer = MusicXmlImporter();
  static const _converter = MusicXmlScoreConverter();

  _InspectorState _state = _InspectorState.empty();
  bool _isLoading = false;
  bool _showRawXml = false;
  bool _showScoreModel = false;

  // ── Import & parse ──────────────────────────────────────────────────────────

  Future<void> _onImportPressed() async {
    setState(() {
      _isLoading = true;
      _showRawXml = false;
      _showScoreModel = false;
    });

    try {
      // MusicXmlImporter handles file picking, .mxl decompression, encoding
      // fallback, and runs MusicXmlParserService (which runs
      // MusicXmlValidatorService) internally.
      final MusicXmlImportResult? result = await _importer.pickAndRead();

      // User cancelled — leave existing state untouched.
      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }

      final parseResult = result.parseResult;

      // ── Case 1: XML could not be parsed at all ───────────────────────────
      if (parseResult.document == null) {
        setState(() {
          _state = _InspectorState.parseError(
            fileName: result.fileName,
            errorMessage: parseResult.errorMessage ?? 'Unknown parse error.',
          );
          _isLoading = false;
        });
        return;
      }

      // ── Extract metadata from the parsed document ────────────────────────
      final metadata = _extractMetadata(parseResult);

      // ── Case 2: Parsed but validation failed ─────────────────────────────
      if (!parseResult.success) {
        setState(() {
          _state = _InspectorState.validationError(
            fileName: result.fileName,
            metadata: metadata,
            rawXml: result.xmlContent,
            errorMessage: parseResult.errorMessage ??
                parseResult.validationErrors.join('\n'),
          );
          _isLoading = false;
        });
        return;
      }

      // ── Case 3: Fully valid — convert to Score domain model ──────────────
      Score? score;
      try {
        score = _converter.convert(parseResult.document!);
      } catch (_) {
        // Conversion failure is non-fatal for the inspector; show what we have.
      }

      setState(() {
        _state = _InspectorState.success(
          fileName: result.fileName,
          metadata: metadata,
          rawXml: result.xmlContent,
          score: score,
        );
        _isLoading = false;
      });
    } on MusicXmlImportException catch (e) {
      setState(() {
        _state = _InspectorState.parseError(
          fileName: _state.fileName ?? 'unknown',
          errorMessage: e.message,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _state = _InspectorState.parseError(
          fileName: _state.fileName ?? 'unknown',
          errorMessage: e.toString(),
        );
        _isLoading = false;
      });
    }
  }

  /// Extracts display metadata from a [MusicXmlParseResult] whose document
  /// is non-null. Works for both success and validation-failure states.
  _ParsedMetadata _extractMetadata(MusicXmlParseResult parseResult) {
    final doc = parseResult.document!;
    final root = doc.rootElement;

    final rootTag = '<${root.name.local}>';

    final workTitle = root
        .findAllElements('work-title')
        .firstOrNull
        ?.innerText
        .trim();
    final movementTitle = root
        .findAllElements('movement-title')
        .firstOrNull
        ?.innerText
        .trim();
    final title = (workTitle?.isNotEmpty == true)
        ? workTitle
        : (movementTitle?.isNotEmpty == true)
            ? movementTitle
            : null;

    final composer = root
        .findAllElements('creator')
        .where((e) => e.getAttribute('type') == 'composer')
        .firstOrNull
        ?.innerText
        .trim();

    final partCount = root.findAllElements('part').length;
    final measureCount = root.findAllElements('measure').length;
    final noteCount = root.findAllElements('note').length;

    return _ParsedMetadata(
      rootTag: rootTag,
      title: (title?.isEmpty == true) ? null : title,
      composer: (composer?.isEmpty == true) ? null : composer,
      partCount: partCount,
      measureCount: measureCount,
      noteCount: noteCount,
      validationErrors: parseResult.validationErrors,
      warnings: parseResult.warnings,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MusicXML Inspector',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'DEV',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A56DB),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Import button ───────────────────────────────────────────────
            ElevatedButton(
              onPressed: _isLoading ? null : _onImportPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF185FA5),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF185FA5).withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '+ Import MusicXML',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),

            const SizedBox(height: 12),

            // ── Status ──────────────────────────────────────────────────────
            _SectionCard(
              label: 'STATUS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusDot(state: _state.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _state.fileName ?? 'No file imported',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                _state.status == _ScreenState.empty
                                    ? FontWeight.w400
                                    : FontWeight.w500,
                            color: _state.status == _ScreenState.empty
                                ? const Color(0xFFAAAAAA)
                                : const Color(0xFF111111),
                            fontStyle:
                                _state.status == _ScreenState.empty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ParseBadge(state: _state.status),
                      const SizedBox(width: 6),
                      _ValidationBadge(state: _state.status),
                    ],
                  ),
                ],
              ),
            ),

            // ── Error / validation error block ──────────────────────────────
            if (_state.errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBlock(
                message: _state.errorMessage!,
                // Distinguish validation errors (have partial metadata) from
                // hard parse errors.
                isValidation:
                    _state.status == _ScreenState.validationError,
              ),
            ],

            // ── Warnings block ───────────────────────────────────────────────
            if (_state.metadata?.warnings.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _WarningBlock(warnings: _state.metadata!.warnings),
            ],

            const SizedBox(height: 12),

            // ── Metadata ────────────────────────────────────────────────────
            _SectionCard(
              label: 'METADATA',
              child: Column(
                children: [
                  _MetaRow(
                    label: 'Root tag',
                    value: _state.metadata?.rootTag,
                    mono: true,
                  ),
                  _MetaRow(label: 'Title', value: _state.metadata?.title),
                  _MetaRow(
                      label: 'Composer',
                      value: _state.metadata?.composer),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Counts ──────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _CountCard(
                    label: 'Parts',
                    value: _state.metadata != null
                        ? '${_state.metadata!.partCount}'
                        : '—',
                    dimmed: _state.metadata == null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountCard(
                    label: 'Measures',
                    value: _state.metadata != null
                        ? '${_state.metadata!.measureCount}'
                        : '—',
                    dimmed: _state.metadata == null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountCard(
                    label: 'Notes',
                    value: _state.metadata != null
                        ? _formatNumber(_state.metadata!.noteCount)
                        : '—',
                    dimmed: _state.metadata == null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Raw XML preview ─────────────────────────────────────────────
            _CollapsibleSection(
              label: 'RAW XML PREVIEW',
              enabled: _state.rawXml != null,
              expanded: _showRawXml,
              onToggle: _state.rawXml != null
                  ? () => setState(() => _showRawXml = !_showRawXml)
                  : null,
              child: _state.rawXml != null
                  ? _MonoPreview(
                      text: _state.rawXml!.length > 2000
                          ? '${_state.rawXml!.substring(0, 2000)}\n\n… (truncated)'
                          : _state.rawXml!,
                    )
                  : null,
            ),

            const SizedBox(height: 8),

            // ── ScoreModel debug ────────────────────────────────────────────
            _CollapsibleSection(
              label: 'SCOREMODEL DEBUG',
              enabled: _state.score != null,
              expanded: _showScoreModel,
              onToggle: _state.score != null
                  ? () =>
                      setState(() => _showScoreModel = !_showScoreModel)
                  : null,
              child: _state.score != null
                  ? _MonoPreview(text: _formatScoreDebug(_state.score!))
                  : null,
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  /// Builds a readable debug dump from the converted [Score] domain model.
  /// This reflects real data from [MusicXmlScoreConverter], not raw XML counts.
  String _formatScoreDebug(Score score) {
    final buf = StringBuffer();
    buf.writeln('Score {');
    buf.writeln('  id:       ${score.id}');
    buf.writeln('  title:    ${score.title}');
    buf.writeln('  composer: ${score.composer}');
    buf.writeln('  parts:    ${score.parts.length}');
    buf.writeln();
    for (final part in score.parts) {
      final totalMeasures = part.measures.length;
      final totalNotes = part.measures
          .expand((m) => m.symbols)
          .length;
      buf.writeln('  Part "${part.name}" (id: ${part.id}) {');
      buf.writeln('    measures: $totalMeasures');
      buf.writeln('    symbols:  $totalNotes');
      if (part.measures.isNotEmpty) {
        final first = part.measures.first;
        if (first.clef != null) {
          buf.writeln('    clef[0]:  ${first.clef!.sign}/${first.clef!.line}');
        }
        if (first.timeSignature != null) {
          buf.writeln(
              '    time[0]:  ${first.timeSignature!.beats}/${first.timeSignature!.beatType}');
        }
        if (first.keySignature != null) {
          buf.writeln(
              '    key[0]:   fifths=${first.keySignature!.fifths}');
        }
      }
      buf.writeln('  }');
    }
    buf.write('}');
    return buf.toString();
  }
}

// ─── Small shared widgets ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String label;
  final Widget child;

  const _SectionCard({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF999999),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final _ScreenState state;

  const _StatusDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _ScreenState.empty           => const Color(0xFFD1D1D1),
      _ScreenState.success         => const Color(0xFF22C55E),
      _ScreenState.parseError      => const Color(0xFFEF4444),
      _ScreenState.validationError => const Color(0xFFF97316),
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ParseBadge extends StatelessWidget {
  final _ScreenState state;

  const _ParseBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _ScreenState.empty           => const _Badge(label: 'Parse: —',    style: _BadgeStyle.neutral),
      _ScreenState.success         => const _Badge(label: 'Parse: OK',   style: _BadgeStyle.success),
      _ScreenState.parseError      => const _Badge(label: 'Parse: FAIL', style: _BadgeStyle.fail),
      _ScreenState.validationError => const _Badge(label: 'Parse: OK',   style: _BadgeStyle.success),
    };
  }
}

class _ValidationBadge extends StatelessWidget {
  final _ScreenState state;

  const _ValidationBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _ScreenState.empty           => const _Badge(label: 'Validation: —',       style: _BadgeStyle.neutral),
      _ScreenState.success         => const _Badge(label: 'Validation: OK',      style: _BadgeStyle.success),
      _ScreenState.parseError      => const _Badge(label: 'Validation: —',       style: _BadgeStyle.neutral),
      _ScreenState.validationError => const _Badge(label: 'Validation: INVALID', style: _BadgeStyle.fail),
    };
  }
}

enum _BadgeStyle { neutral, success, fail }

class _Badge extends StatelessWidget {
  final String label;
  final _BadgeStyle style;

  const _Badge({required this.label, required this.style});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (style) {
      _BadgeStyle.success => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      _BadgeStyle.fail    => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _BadgeStyle.neutral => (const Color(0xFFEFEFEF), const Color(0xFFAAAAAA)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: style == _BadgeStyle.neutral
            ? Border.all(color: const Color(0xFFE0E0E0), width: 0.5)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final bool isValidation;

  const _ErrorBlock({required this.message, this.isValidation = false});

  @override
  Widget build(BuildContext context) {
    // Validation errors use orange; hard parse errors use red.
    final (bg, border, labelColor, textColor) = isValidation
        ? (
            const Color(0xFFFFF7ED),
            const Color(0xFFFED7AA),
            const Color(0xFFC2410C),
            const Color(0xFF7C2D12),
          )
        : (
            const Color(0xFFFFF5F5),
            const Color(0xFFFCA5A5),
            const Color(0xFFB91C1C),
            const Color(0xFF7F1D1D),
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isValidation ? 'VALIDATION ERROR' : 'ERROR',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: labelColor,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontSize: 11.5,
              color: textColor,
              fontFamily: 'monospace',
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBlock extends StatelessWidget {
  final List<String> warnings;

  const _WarningBlock({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WARNINGS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB45309),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          ...warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $w',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF78350F),
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool mono;

  const _MetaRow({required this.label, this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final isEmpty = value == null || value!.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF888888)),
            ),
          ),
          Expanded(
            child: Text(
              isEmpty ? '—' : value!,
              style: TextStyle(
                fontSize: mono ? 11 : 12,
                color: isEmpty
                    ? const Color(0xFFBBBBBB)
                    : const Color(0xFF111111),
                fontStyle:
                    isEmpty ? FontStyle.italic : FontStyle.normal,
                fontFamily: mono ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final String value;
  final bool dimmed;

  const _CountCard({
    required this.label,
    required this.value,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.4 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF999999))),
          ],
        ),
      ),
    );
  }
}

class _MonoPreview extends StatelessWidget {
  final String text;

  const _MonoPreview({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFFF0F0F0),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10.5,
          color: Color(0xFF333333),
          height: 1.5,
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool expanded;
  final VoidCallback? onToggle;
  final Widget? child;

  const _CollapsibleSection({
    required this.label,
    required this.enabled,
    required this.expanded,
    this.onToggle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8E8E8), width: 0.5),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF999999),
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      expanded ? 'Hide ▴' : 'Show ▾',
                      style: TextStyle(
                        fontSize: 11,
                        color: enabled
                            ? const Color(0xFF185FA5)
                            : const Color(0xFFBBBBBB),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded && child != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                child: child!,
              ),
          ],
        ),
      ),
    );
  }
}
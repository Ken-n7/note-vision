import 'package:flutter/material.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_page_thumbnail.dart';
import 'package:note_vision/core/widgets/tappable_button.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/musicXML/musicxml_import_exception.dart';
import 'package:note_vision/features/musicXML/musicxml_import_result.dart';
import 'package:note_vision/features/musicXML/musicxml_importer.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';

class ImportScoreScreen extends StatefulWidget {
  const ImportScoreScreen({super.key});

  @override
  State<ImportScoreScreen> createState() => _ImportScoreScreenState();
}

class _ImportScoreScreenState extends State<ImportScoreScreen> {
  static const _xmlConverter = MusicXmlScoreConverter();
  final _importer = MusicXmlImporter();

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
          tooltip: 'Back',
          onPressed: _goToCollection,
        ),
        title: const Text(
          'Note Vision',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            color: _textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth > constraints.maxHeight;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: isLandscape
                ? _buildLandscapeContent()
                : _buildPortraitContent(),
          );
        },
      ),
    );
  }

  Widget _buildPortraitContent() {
    return Column(
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
          'Import a MusicXML file (.xml, .musicxml or .mxl), preview it, then continue to the editor.',
          style: TextStyle(
            fontSize: 14,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: _buildPreviewArea()),
        const SizedBox(height: 14),
        _buildMessages(),
        _buildActionRow(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLandscapeContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
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
                'Import a MusicXML file (.xml, .musicxml or .mxl), preview it, then continue to the editor.',
                style: TextStyle(
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildPreviewArea()),
              const SizedBox(height: 12),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildMessages(),
                _buildActionRow(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessages() {
    if (_warnings.isEmpty && _errors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
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
            color: AppColors.error,
            messages: _errors,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildPreviewArea() {
    final previewBackground = _importedScore != null ? const Color(0xFFF9FAFB) : _surface;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: previewBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio:
            EditorLayoutPolicy.standard.pageWidth /
            EditorLayoutPolicy.standard.pageHeight,
        // The first page as the editor lays it out, scaled to fit.
        child: _importedScore != null
            ? LayoutBuilder(
                builder: (context, box) => ScorePageThumbnail(
                  score: _importedScore!,
                  pageIndex: 0,
                  cardWidth: box.maxWidth,
                  height: box.maxHeight,
                ),
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
              ? 'Import a MusicXML file below'
              : 'Selected: $_selectedFileName',
          style: const TextStyle(
            fontSize: 12,
            color: _textSecondary,
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
          TappableButton(
            onPressed: _cancelSelection,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border, width: 1),
              ),
              child: const Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
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
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: TappableButton(
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

  Widget _buildContinueButton() {
    return TappableButton(
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

  Future<void> _importMusicXml() async {
    setState(() {
      _isLoading = true;
      _errors = const [];
      _warnings = const [];
      _importedScore = null;
    });

    // Reads .xml, .musicxml and compressed .mxl files.
    final MusicXmlImportResult? imported;
    try {
      imported = await _importer.pickAndRead();
    } on MusicXmlImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [e.message];
        _isLoading = false;
      });
      return;
    }

    if (!mounted) return;
    if (imported == null) {
      setState(() => _isLoading = false);
      return;
    }

    final parsed = imported.parseResult;
    if (!parsed.success || parsed.document == null) {
      setState(() {
        _selectedFileName = imported!.fileName;
        _errors = parsed.validationErrors.isNotEmpty
            ? parsed.validationErrors
            : [parsed.errorMessage ?? 'Invalid MusicXML content.'];
        _warnings = parsed.warnings;
        _isLoading = false;
      });
      return;
    }

    try {
      final score = _xmlConverter.convert(parsed.document!);
      setState(() {
        _selectedFileName = imported!.fileName;
        _errors = const [];
        _warnings = parsed.warnings;
        _importedScore = score;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Import failed: $e');
      setState(() {
        _selectedFileName = imported!.fileName;
        _errors = const ['Could not import MusicXML file.'];
        _warnings = const [];
        _importedScore = null;
        _isLoading = false;
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

  void _goToCollection() => Navigator.of(context).maybePop();
}

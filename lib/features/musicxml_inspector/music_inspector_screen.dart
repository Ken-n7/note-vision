import 'package:flutter/material.dart';

import '../../core/widgets/inspector_shared_widgets.dart';
import '../detection_inspector/detection_inspector_screen.dart';
import 'controller/musicxml_inspector_controller.dart';
import 'model/inspector_state.dart';
import 'widgets/collapsible_section.dart';
import 'widgets/counts_section.dart';
import 'widgets/error_block.dart';
import 'widgets/metadata_section.dart';
import 'widgets/score_debug_panel.dart';
import 'widgets/status_section.dart';

class MusicXmlInspectorScreen extends StatefulWidget {
  const MusicXmlInspectorScreen({super.key});

  @override
  State<MusicXmlInspectorScreen> createState() =>
      _MusicXmlInspectorScreenState();
}

class _MusicXmlInspectorScreenState extends State<MusicXmlInspectorScreen> {
  final _controller = MusicXmlInspectorController();

  bool _showRawXml = false;
  bool _showScoreModel = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onImportPressed() async {
    setState(() {
      _showRawXml = false;
      _showScoreModel = false;
    });
    await _controller.onImportPressed();
    if (mounted) setState(() {});
  }

  void _goToDetectionInspector() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DetectionInspectorScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final isLoading = _controller.isLoading;

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
            // ── Import button ─────────────────────────────────────────────
            ElevatedButton(
              onPressed: isLoading ? null : _onImportPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF185FA5),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF185FA5).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: isLoading
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

            const SizedBox(height: 10),

            // ── Detection Inspector shortcut ──────────────────────────────
            OutlinedButton.icon(
              onPressed: _goToDetectionInspector,
              icon: const Icon(Icons.biotech_outlined, size: 16),
              label: const Text(
                'Detection Inspector',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF185FA5),
                side: const BorderSide(color: Color(0xFF185FA5), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Status ────────────────────────────────────────────────────
            StatusSection(state: state),

            // ── Error block ───────────────────────────────────────────────
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              ErrorBlock(
                message: state.errorMessage!,
                isValidation: state.status == ScreenState.validationError,
              ),
            ],

            // ── Warnings block ────────────────────────────────────────────
            if (state.metadata?.warnings.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              WarningBlock(warnings: state.metadata!.warnings),
            ],

            const SizedBox(height: 12),

            // ── Metadata ──────────────────────────────────────────────────
            MetadataSection(metadata: state.metadata),

            const SizedBox(height: 12),

            // ── Counts ────────────────────────────────────────────────────
            CountsSection(metadata: state.metadata),

            const SizedBox(height: 12),

            // ── Raw XML preview ───────────────────────────────────────────
            CollapsibleSection(
              label: 'RAW XML PREVIEW',
              enabled: state.rawXml != null,
              expanded: _showRawXml,
              onToggle: state.rawXml != null
                  ? () => setState(() => _showRawXml = !_showRawXml)
                  : null,
              child: state.rawXml != null
                  ? MonoPreview(
                      text: state.rawXml!.length > 2000
                          ? '${state.rawXml!.substring(0, 2000)}\n\n… (truncated)'
                          : state.rawXml!,
                    )
                  : null,
            ),

            const SizedBox(height: 8),

            // ── ScoreModel debug ──────────────────────────────────────────
            CollapsibleSection(
              label: 'SCOREMODEL DEBUG',
              enabled: state.score != null,
              expanded: _showScoreModel,
              onToggle: state.score != null
                  ? () =>
                      setState(() => _showScoreModel = !_showScoreModel)
                  : null,
              child: state.score != null
                  ? ScoreDebugPanel(score: state.score!)
                  : null,
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
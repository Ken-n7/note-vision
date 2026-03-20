// lib/features/dev/detection_inspector/detection_inspector_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller/detection_inspector_controller.dart';
import 'widgets/di_action_bar.dart';
import 'widgets/di_detection_summary.dart';
import 'widgets/di_issues_section.dart';
import 'widgets/di_raw_json_panel.dart';
import 'widgets/di_score_preview.dart';
import 'widgets/di_status_badge.dart';

class DetectionInspectorScreen extends StatefulWidget {
  const DetectionInspectorScreen({super.key});

  @override
  State<DetectionInspectorScreen> createState() =>
      _DetectionInspectorScreenState();
}

class _DetectionInspectorScreenState extends State<DetectionInspectorScreen> {
  final _ctrl = DetectionInspectorController();
  bool _showRawJson = false;

  // ── Tokens ─────────────────────────────────────────────────────────────────
  static const _bg       = Color(0xFF0F1117);
  static const _surface  = Color(0xFF181C27);
  static const _border   = Color(0xFF252A3A);
  static const _accent   = Color(0xFF4F8EF7);
  static const _textPri  = Color(0xFFE8ECF4);
  static const _textSec  = Color(0xFF6B7390);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onReset() {
    setState(() => _showRawJson = false);
    _ctrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: _border),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: _textPri),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _accent.withOpacity(0.4)),
            ),
            child: const Text(
              'DEV',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _accent,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Detection Inspector',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _textPri,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        if (_ctrl.status != InspectorStatus.idle)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _onReset,
              child: const Text(
                'Reset',
                style: TextStyle(fontSize: 13, color: _textSec),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Action bar
          DiActionBar(controller: _ctrl),

          const SizedBox(height: 20),

          // Status
          DiStatusBadge(controller: _ctrl),

          const SizedBox(height: 16),

          // Issues (warnings + errors)
          if (_ctrl.status != InspectorStatus.idle) ...[
            DiIssuesSection(controller: _ctrl),
            const SizedBox(height: 16),
          ],

          // Detection summary (after load)
          if (_ctrl.detection != null) ...[
            DiDetectionSummary(controller: _ctrl),
            const SizedBox(height: 16),
          ],

          // Score preview (after mapping)
          if (_ctrl.mappingResult != null) ...[
            DiScorePreview(controller: _ctrl),
            const SizedBox(height: 16),
          ],

          // Raw JSON toggle
          if (_ctrl.rawJsonPretty != null)
            DiRawJsonPanel(
              json: _ctrl.rawJsonPretty!,
              expanded: _showRawJson,
              onToggle: () => setState(() => _showRawJson = !_showRawJson),
            ),
        ],
      ),
    );
  }
}
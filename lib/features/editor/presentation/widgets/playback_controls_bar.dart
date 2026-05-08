import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/playback_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Playback controls bar rendered at the bottom of the editor screen.
///
/// Contains: play/pause toggle, stop button, tempo stepper (+/- 5 BPM).
/// Connects directly to [PlaybackService.instance] streams.
class PlaybackControlsBar extends StatefulWidget {
  const PlaybackControlsBar({
    super.key,
    required this.onPlay,
    required this.onResume,
    required this.onPause,
    required this.onStop,
    required this.onTempoChanged,
    this.isEmpty = false,
  });

  final VoidCallback onPlay;
  final VoidCallback onResume;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final ValueChanged<int> onTempoChanged;

  /// When true all controls are disabled and greyed out (empty score).
  final bool isEmpty;

  @override
  State<PlaybackControlsBar> createState() => _PlaybackControlsBarState();
}

class _PlaybackControlsBarState extends State<PlaybackControlsBar> {
  final _svc = PlaybackService.instance;
  late double _tempo;

  void _adjustTempo(int delta) {
    final next = (_tempo.round() + delta).clamp(40, 200).toDouble();
    setState(() => _tempo = next);
    widget.onTempoChanged(next.round());
  }

  @override
  void initState() {
    super.initState();
    _tempo = _svc.tempo.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: _svc.stateStream,
      initialData: PlaybackState(status: _svc.status),
      builder: (context, snap) {
        final state = snap.data ?? PlaybackState(status: PlaybackStatus.stopped);
        final isPlaying = state.isPlaying;
        final isPaused = state.isPaused;
        final isStopped = state.isStopped;
        final hasError = state.status == PlaybackStatus.error;
        final disabled = widget.isEmpty;

        return Container(
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // ── Play / Pause toggle ──────────────────────────────────
              _ControlButton(
                icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: isPlaying ? 'Pause' : 'Play',
                filled: true,
                disabled: disabled || hasError,
                onPressed: () {
                  if (isPlaying) {
                    widget.onPause();
                  } else if (isPaused) {
                    widget.onResume();
                  } else {
                    widget.onPlay();
                  }
                },
              ),
              const SizedBox(width: 4),

              // ── Stop ────────────────────────────────────────────────
              _ControlButton(
                icon: Icons.stop_rounded,
                tooltip: 'Stop',
                disabled: disabled || isStopped || hasError,
                onPressed: widget.onStop,
              ),
              const SizedBox(width: 12),

              // ── Divider ─────────────────────────────────────────────
              Container(width: 1, height: 24, color: AppColors.border),
              const SizedBox(width: 12),

              // ── Tempo stepper ─────────────────────────────────────────
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.speed_rounded, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    _TempoButton(
                      icon: Icons.remove,
                      disabled: disabled || _tempo <= 40,
                      onPressed: () => _adjustTempo(-1),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${_tempo.round()} BPM',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: disabled
                              ? AppColors.textSecondary.withValues(alpha: 0.4)
                              : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _TempoButton(
                      icon: Icons.add,
                      disabled: disabled || _tempo >= 200,
                      onPressed: () => _adjustTempo(1),
                    ),
                  ],
                ),
              ),

              // ── Error indicator ──────────────────────────────────────
              if (hasError) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: state.error ?? 'Playback error',
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Internal widgets
// ---------------------------------------------------------------------------

class _TempoButton extends StatefulWidget {
  const _TempoButton({
    required this.icon,
    required this.onPressed,
    required this.disabled,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool disabled;

  @override
  State<_TempoButton> createState() => _TempoButtonState();
}

class _TempoButtonState extends State<_TempoButton> {
  Timer? _holdTimer;
  bool _pressed = false;

  void _onPointerDown(PointerDownEvent _) {
    if (widget.disabled) return;
    setState(() => _pressed = true);
    widget.onPressed();
    // After 400 ms start repeating every 80 ms
    _holdTimer = Timer(const Duration(milliseconds: 400), () {
      _holdTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (!widget.disabled) widget.onPressed();
      });
    });
  }

  void _cancel() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted) setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.disabled
        ? AppColors.textSecondary.withValues(alpha: 0.3)
        : AppColors.textSecondary;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Material(
          color: widget.disabled
              ? AppColors.border.withValues(alpha: 0.3)
              : _pressed
                  ? AppColors.border
                  : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          child: Center(child: Icon(widget.icon, size: 14, color: color)),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
    this.disabled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled
        ? AppColors.textSecondary.withValues(alpha: 0.3)
        : AppColors.textPrimary;

    if (filled) {
      return Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Material(
            color: disabled
                ? AppColors.border.withValues(alpha: 0.4)
                : AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(17),
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: disabled ? null : onPressed,
              child: Icon(icon, size: 20, color: disabled ? effectiveColor : AppColors.accent),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          onPressed: disabled ? null : onPressed,
          icon: Icon(icon, size: 18),
          color: effectiveColor,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

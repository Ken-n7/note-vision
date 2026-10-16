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
    required this.totalMeasures,
    required this.onSeek,
    this.measuresPerPart,
    this.isEmpty = false,
  });

  final VoidCallback onPlay;
  final VoidCallback onResume;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final ValueChanged<int> onTempoChanged;
  /// Scrubber steps: measures of every part in reading order, part by part.
  final int totalMeasures;

  /// Measures in one part, to place a (part, measure) position on the
  /// scrubber; null when the score has a single part.
  final int? measuresPerPart;
  final ValueChanged<int> onSeek;

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

              // ── Scrubber ──────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _Scrubber(
                    totalMeasures: widget.totalMeasures,
                    measuresPerPart: widget.measuresPerPart,
                    isPlaying: isPlaying,
                    onSeek: widget.onSeek,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ── Divider ───────────────────────────────────────────────
              Container(width: 1, height: 24, color: AppColors.border),
              const SizedBox(width: 8),

              // ── Tempo stepper ─────────────────────────────────────────
              const Icon(Icons.speed_rounded, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              _TempoButton(
                icon: Icons.remove,
                label: 'Slower',
                disabled: disabled || _tempo <= 40,
                onPressed: () => _adjustTempo(-1),
              ),
              const SizedBox(width: 4),
              Text(
                '${_tempo.round()}',
                style: TextStyle(
                  color: disabled
                      ? AppColors.textSecondary.withValues(alpha: 0.4)
                      : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              _TempoButton(
                icon: Icons.add,
                label: 'Faster',
                disabled: disabled || _tempo >= 200,
                onPressed: () => _adjustTempo(1),
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

class _Scrubber extends StatefulWidget {
  const _Scrubber({
    required this.totalMeasures,
    required this.measuresPerPart,
    required this.isPlaying,
    required this.onSeek,
  });

  final int totalMeasures;
  final int? measuresPerPart;
  final bool isPlaying;
  final ValueChanged<int> onSeek;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  final _svc = PlaybackService.instance;
  double? _dragFraction;

  double _toFraction(PlaybackPosition pos) {
    if (widget.totalMeasures <= 0) return 0;
    if (pos == PlaybackPosition.none) return 0;
    final step =
        pos.partIndex * (widget.measuresPerPart ?? 0) + pos.measureIndex;
    return (step / widget.totalMeasures).clamp(0.0, 1.0);
  }

  void _onDragStart(DragStartDetails d, double width) {
    if (!widget.isPlaying) return;
    setState(() => _dragFraction = (d.localPosition.dx / width).clamp(0.0, 1.0));
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    if (!widget.isPlaying) return;
    setState(() => _dragFraction = (d.localPosition.dx / width).clamp(0.0, 1.0));
  }

  void _onDragEnd(DragEndDetails _) {
    if (_dragFraction == null) return;
    final measure = (_dragFraction! * widget.totalMeasures)
        .round()
        .clamp(0, (widget.totalMeasures - 1).clamp(0, widget.totalMeasures));
    setState(() => _dragFraction = null);
    widget.onSeek(measure);
  }

  void _onTap(TapUpDetails d, double width) {
    if (!widget.isPlaying) return;
    final f = (d.localPosition.dx / width).clamp(0.0, 1.0);
    final measure = (f * widget.totalMeasures)
        .round()
        .clamp(0, (widget.totalMeasures - 1).clamp(0, widget.totalMeasures));
    widget.onSeek(measure);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackPosition>(
      stream: _svc.positionStream,
      initialData: PlaybackPosition.none,
      builder: (context, snap) {
        final fraction = _dragFraction ?? _toFraction(snap.data ?? PlaybackPosition.none);
        final active = widget.isPlaying;
        final trackColor = AppColors.border;
        final fillColor = active ? AppColors.accent : AppColors.textSecondary.withValues(alpha: 0.3);

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              onHorizontalDragStart: (d) => _onDragStart(d, width),
              onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
              onHorizontalDragEnd: _onDragEnd,
              onTapUp: (d) => _onTap(d, width),
              child: SizedBox(
                // Taller than it looks, so the thumb is easy to grab.
                height: 36,
                width: width,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Track
                      Positioned.fill(
                        child: Center(
                          child: Container(height: 2, color: trackColor),
                        ),
                      ),
                      // Fill
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: width * fraction,
                        child: Center(
                          child: Container(height: 2, color: fillColor),
                        ),
                      ),
                      // Thumb
                      Positioned(
                        left: (width * fraction - 5).clamp(0, width - 10),
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: fillColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TempoButton extends StatefulWidget {
  const _TempoButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.disabled,
  });

  final IconData icon;
  final String label;
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

    return Semantics(
      button: true,
      enabled: !widget.disabled,
      label: '${widget.label} tempo',
      onTap: widget.disabled ? null : widget.onPressed,
      excludeSemantics: true,
      child: Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Material(
          color: widget.disabled
              ? AppColors.border.withValues(alpha: 0.3)
              : _pressed
                  ? AppColors.border
                  : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          child: Center(child: Icon(widget.icon, size: 16, color: color)),
        ),
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
          width: 40,
          height: 40,
          child: Material(
            color: disabled
                ? AppColors.border.withValues(alpha: 0.4)
                : AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: disabled ? null : onPressed,
              child: Icon(icon, size: 22, color: disabled ? effectiveColor : AppColors.accent),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          onPressed: disabled ? null : onPressed,
          icon: Icon(icon, size: 20),
          color: effectiveColor,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

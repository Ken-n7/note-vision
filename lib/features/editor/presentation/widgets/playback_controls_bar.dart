import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/playback_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Responsive transport and tempo controls using the editor's playback service.
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
    this.measureCounts,
    this.initialMeasure = 0,
    this.isEmpty = false,
    this.isLoading = false,
    this.playbackService,
  });

  final VoidCallback onPlay, onResume, onPause, onStop;
  final ValueChanged<int> onTempoChanged, onSeek;
  final int totalMeasures, initialMeasure;
  final int? measuresPerPart;
  final List<int>? measureCounts;
  final bool isEmpty, isLoading;
  final PlaybackService? playbackService;

  @override
  State<PlaybackControlsBar> createState() => _PlaybackControlsBarState();
}

class _PlaybackControlsBarState extends State<PlaybackControlsBar> {
  late int _tempo;
  double? _dragStep;
  PlaybackService get _service =>
      widget.playbackService ?? PlaybackService.instance;

  @override
  void initState() {
    super.initState();
    _tempo = _service.tempo;
  }

  @override
  void didUpdateWidget(covariant PlaybackControlsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackService != widget.playbackService) {
      _tempo = _service.tempo;
      _dragStep = null;
    }
    if (oldWidget.totalMeasures != widget.totalMeasures) _dragStep = null;
  }

  void _adjustTempo(int delta) {
    final next = (_tempo + delta).clamp(40, 200);
    if (next == _tempo) return;
    setState(() => _tempo = next);
    widget.onTempoChanged(next);
  }

  int _step(PlaybackPosition position) {
    if (position.isNone) return widget.initialMeasure;
    final counts = widget.measureCounts;
    if (counts == null) {
      return position.partIndex * (widget.measuresPerPart ?? 0) +
          position.measureIndex;
    }
    return counts
            .take(position.partIndex)
            .fold(0, (sum, count) => sum + count) +
        position.measureIndex;
  }

  String _positionLabel(int step) {
    final counts = widget.measureCounts;
    if (counts != null && counts.length > 1) {
      var start = 0;
      for (var part = 0; part < counts.length; part++) {
        if (step < start + counts[part]) {
          return 'Staff ${part + 1}, measure ${step - start + 1}';
        }
        start += counts[part];
      }
    }
    return 'Measure ${step + 1} of ${widget.totalMeasures}';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: _service.stateStream,
    initialData: PlaybackState(status: _service.status),
    builder: (context, stateSnapshot) => StreamBuilder<PlaybackPosition>(
      stream: _service.positionStream,
      initialData: _service.position,
      builder: (context, positionSnapshot) {
        final state =
            stateSnapshot.data ?? PlaybackState(status: _service.status);
        final position = positionSnapshot.data ?? PlaybackPosition.none;
        final error = state.status == PlaybackStatus.error;
        final disabled = widget.isEmpty;
        final maxStep = (widget.totalMeasures - 1).clamp(0, 1 << 30).toDouble();
        final step = (_dragStep ?? _step(position).toDouble()).clamp(
          0.0,
          maxStep,
        );
        final current = step.round();
        final transport = <Widget>[
          IconButton.filledTonal(
            tooltip: widget.isLoading
                ? 'Loading playback'
                : error
                ? 'Retry playback'
                : state.isPlaying
                ? 'Pause'
                : state.isPaused
                ? 'Resume'
                : 'Play',
            onPressed: disabled || widget.isLoading
                ? null
                : () {
                    if (state.isPlaying) {
                      widget.onPause();
                    } else if (state.isPaused) {
                      widget.onResume();
                    } else {
                      widget.onPlay();
                    }
                  },
            style: IconButton.styleFrom(
              minimumSize: const Size.square(48),
              backgroundColor: AppColors.accent.withValues(alpha: .15),
              foregroundColor: AppColors.accent,
            ),
            icon: widget.isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    error
                        ? Icons.refresh_rounded
                        : state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
          ),
          IconButton(
            tooltip: 'Stop',
            onPressed:
                disabled ||
                    (state.isStopped && !widget.isLoading && position.isNone)
                ? null
                : widget.onStop,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.stop_rounded),
          ),
        ];
        final progress = Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'Playback position',
                child: Slider(
                  activeColor: AppColors.accent,
                  inactiveColor: AppColors.border,
                  key: const ValueKey('playback-scrubber'),
                  value: step,
                  min: 0,
                  max: maxStep,
                  divisions: maxStep > 0 ? maxStep.toInt() : null,
                  label: _positionLabel(current),
                  semanticFormatterCallback: (value) =>
                      _positionLabel(value.round()),
                  onChanged: disabled || widget.isLoading || maxStep == 0
                      ? null
                      : (value) => setState(() => _dragStep = value),
                  onChangeEnd: disabled || widget.isLoading || maxStep == 0
                      ? null
                      : (value) {
                          setState(() => _dragStep = null);
                          widget.onSeek(value.round());
                        },
                ),
              ),
            ),
            Tooltip(
              message: disabled
                  ? 'No measures to play'
                  : _positionLabel(current),
              child: Text(
                disabled ? '—' : '${current + 1}/${widget.totalMeasures}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
        final tempo = Semantics(
          label: 'Tempo',
          value: '$_tempo beats per minute',
          child: Row(
            children: [
              _TempoButton(
                icon: Icons.remove_rounded,
                label: 'Slower tempo',
                disabled: disabled || _tempo <= 40,
                onPressed: () => _adjustTempo(-1),
              ),
              Expanded(
                child: Text(
                  '$_tempo BPM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: disabled
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _TempoButton(
                icon: Icons.add_rounded,
                label: 'Faster tempo',
                disabled: disabled || _tempo >= 200,
                onPressed: () => _adjustTempo(1),
              ),
            ],
          ),
        );
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 600 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.4;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ...transport,
                        Expanded(child: progress),
                        if (!stacked) ...[
                          const SizedBox(width: 16),
                          SizedBox(width: 192, child: tempo),
                        ],
                      ],
                    ),
                    if (stacked)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: tempo,
                        ),
                      ),
                    if (error)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Playback unavailable. Tap Retry to try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class _TempoButton extends StatefulWidget {
  const _TempoButton({
    required this.icon,
    required this.label,
    required this.disabled,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback onPressed;
  @override
  State<_TempoButton> createState() => _TempoButtonState();
}

class _TempoButtonState extends State<_TempoButton> {
  Timer? _timer;
  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didUpdateWidget(covariant _TempoButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabled) _cancel();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPressStart: widget.disabled
        ? null
        : (_) {
            widget.onPressed();
            _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
              if (mounted && !widget.disabled) widget.onPressed();
            });
          },
    onLongPressEnd: (_) => _cancel(),
    onLongPressCancel: _cancel,
    child: IconButton(
      tooltip: widget.label,
      onPressed: widget.disabled ? null : widget.onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(widget.icon, size: 20),
    ),
  );
}

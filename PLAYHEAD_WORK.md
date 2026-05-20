# Playhead Smoothness — Work Log

## Status: In Testing
Code is complete and compiles clean. Needs device testing to confirm.

---

## What Was Done

### Root cause (original)
`_PlaybackVisualClock` — a wall-clock timer that drifted from MIDI overhead and broke
completely on tempo changes (sawtooth: forward sweep → backward snap on every resync).

### Fix applied
Full rewrite across 3 files. No wall-clock timer. No accumulated base-ms math.

**New architecture:**
1. `PlaybackService` emits `positionStream` with `durationMs` + `symbolIndex` per note
2. `_EditorShellScreenState` increments `_playheadEpoch` on each event → passes to `_NotationArea`
3. `_NotationAreaState.didUpdateWidget` detects epoch change → sets controller duration to
   `pos.durationMs` → calls `_playheadController.forward(from: 0.0)`
4. `AnimatedBuilder` rebuilds every vsync: `playbackProgress = _playheadController.value` (0→1)
5. Painter receives `playheadSymbolIndex` + T (0→1) → looks up current slot X and next slot X
   directly from measure geometry → lerps. No base-ms accumulation anywhere.

### Files changed
- `lib/features/editor/presentation/editor_shell_screen.dart`
  - Removed: `_PlaybackVisualClock`, `_PlaybackTimeline`, `_PlaybackTimelinePosition`,
    `_PlaybackTimelineSpan` classes (all deleted)
  - Removed state fields: `_playbackTimeline`, `_playheadSymbolBaseMs`,
    `_playheadSymbolBaseDuration`
  - Added state fields: `_playheadEpoch`, `_playheadSymbolIndex`, `_playheadNoteDurationMs`
  - `_NotationArea` widget: removed `playbackTimeline`, `playheadSymbolBaseMs`,
    `playheadSymbolBaseDuration`; added `playheadSymbolIndex`
  - `_NotationAreaState.didUpdateWidget`: epoch-based `forward(from: 0.0)` restart
  - `_buildScoreNotationViewer`: passes `playbackT = controller.value` and `playheadSymbolIndex`

- `lib/core/widgets/score_notation_viewer.dart`
  - Added `playheadSymbolIndex` parameter
  - Removed `playheadPageBaseMs` parameter

- `lib/core/widgets/score_notation/score_notation_painter.dart`
  - Added `playheadSymbolIndex` field
  - Removed `playheadPageBaseMs` field
  - `_drawPlaybackPlayhead` rewritten: slot-geometry lerp instead of base-ms waypoints
  - Removed `_buildRowWaypoints` and `_interpolatePageX` methods

---

## What Still Needs Testing

1. **Slow tempo** — should now sweep smoothly (formula bug was: `defaultTempo/tempo` instead
   of `tempo/defaultTempo` in the old base-ms conversion — now irrelevant, formula gone)
2. **Fast tempo** — still looks "choppy" at high BPM because fewer frames per short note
   (physics, not a bug — a 125ms note at 240 BPM = 7 frames at 60fps)
3. **Within-row measure transitions** — should now be smooth (old barline snap eliminated;
   next-symbol X is used directly)
4. **Cross-row transitions** — still an instant jump from right barline to left start of next
   row. This is correct sheet-music behavior, not a bug.

---

## Potential Next Step (if testing shows issues)

**Isolate playhead into its own painter layer** — the score (staff lines, noteheads, clefs)
is static during playback. Currently, every `AnimationController` tick redraws the entire
canvas. A separate top-layer `CustomPainter` for just the red line would let the score
paint once and cache, reducing repaint cost on complex pages.

Only worth doing if frame drops are visible on a dense 20-measure multi-part page.

# Note Vision — Project Context

> Feed this file to Claude at the start of every session.
> Keep it updated as decisions change, tickets are added, or bugs are found.
> It is intentionally concise — specs live in Jira, code lives in the repo.

---

## What This App Is

Note Vision is a fully offline Flutter mobile app for Optical Music Recognition (OMR).
The user photographs printed sheet music, the app detects musical symbols using an on-device
TFLite YOLO model, reconstructs the symbols into a digital score, lets the user correct
mistakes in an editor, then exports or plays back the result. No internet. No server. Everything on-device.

**Target users:** Music students, teachers, musicians who want to digitize printed scores quickly.

**Platform:** Android + iOS (Flutter). Also builds for Linux desktop but mobile is primary.

---

## Team

| Name | Role | Jira Handle |
|------|------|-------------|
| Canete | Backend / logic / reconstruction / ML | Lebrown |
| Boleche | UI / screens / widgets | Leche |
| Galanza | QA / test assets / regression | Lalay |

---

## Tech Stack

| Concern | Library / Tool |
|---------|---------------|
| Framework | Flutter (Dart) |
| ML inference | tflite_flutter 0.12.1 |
| ML model | YOLO — 57 music symbol classes |
| Image processing | image 4.8.0 |
| XML parsing | xml 6.5.0 |
| File picking | file_picker 8.1.2 |
| Camera / gallery | camera 0.12.0, image_picker 1.1.2 |
| Archive (.mxl) | archive 4.0.7 |
| State management | provider 6.1.5, ChangeNotifier |
| Local storage | shared_preferences, path_provider |
| PDF export | pdf ^3.11.1 |
| Audio playback | flutter_midi_pro 3.1.6 |
| Testing | flutter_test, mocktail, mockito |

---

## Pipeline — How the App Works

```
Camera / Gallery / MusicXML file
        ↓
1. Preprocessing
   BasicImagePreprocessor — grayscale, orientation-corrected, full resolution
        ↓
2. Staff Line Detection
   HorizontalProjectionStaffDetector — finds 5 line Y positions per stave
   Populates DetectedStaff.lineYs for pitch reconstruction
        ↓
3. Symbol Detection
   TfliteSymbolDetector — full image stretched to 640×640 (no tiling/letterbox)
   YOLO on-device int8, NMS, confidence 0.75 threshold
   combStaff detections → DetectedStaff (model-detected staves, preferred over projector)
   musical symbol detections → DetectedSymbol list
   SyntheticStaffBuilder fallback when neither source produces staves
        ↓
4. Reconstruction Pipeline
   StaffAssigner → MeasureGrouper → StemAssociator
   → SignatureInferrer → SemanticInferrer → PitchCalculator → ScoreBuilder
   One Part produced per detected staff (Treble, Bass, Staff N...)
   Returns ScoreModel
        ↓
5. Editor
   EditorShellScreen — CustomPainter notation viewer
   Symbol selection, pitch move, accidental toggle, delete, duration change,
   drag-to-delete, drag-to-reorder, undo/redo (50 levels)
   insert note/rest via drag-from-palette (no inspector button)
        ↓
6. Export / Playback
   MusicXML export, PDF export, flutter_midi_pro audio playback
```

---

## Architecture — Key Files

```
lib/
  main.dart                          App entry, dark theme, route setup
  core/
    models/                          Score, Part, Measure, Note, Rest,
                                     Clef, KeySignature, TimeSignature, ScoreSymbol
    widgets/
      score_notation_viewer.dart     CustomPainter staff notation viewer (main editor canvas)
      score_notation/
        score_notation_painter.dart  All drawing logic — staff, notes, rests, clef, sigs
        staff_pitch_mapper.dart      Pitch ↔ staff Y position math
        notation_layout.dart         Row/measure layout calculations
    theme/app_theme.dart             Dark theme tokens (AppColors)
    services/
      image_storage_service.dart     Save/load scanned image paths
      user_profile_service.dart      Username + photo in shared_preferences
      playback_converter.dart        Pure-Dart Score→PlaybackEvent conversion (no platform deps)
      playback_service.dart          Singleton MIDI playback service via flutter_midi_pro

  features/
    landing/                         LandingScreen — entry point
    collection/                      CollectionScreen — saved score grid + project list (merged)
    capture/                         CaptureScreen — camera + gallery
    scan/                            ScanScreen + ScanViewModel — pipeline orchestrator
    preprocessing/                   BasicImagePreprocessor
    detection/                       TfliteSymbolDetector, DetectionResult models
    mapping/                         Full reconstruction pipeline
      domain/
        detection_to_score_mapper_service.dart   Main mapper entry point
        internal/
          staff_assigner.dart
          measure_grouper.dart
          stem_associator.dart
          signature_inferrer.dart
          semantic_inferrer.dart
          pitch_calculator.dart
          score_builder.dart
          synthetic_staff_builder.dart   Estimates staff geometry from notehead positions
    editor/                          EditorShellScreen, EditorState, EditorActions
      model/
        editor_state.dart            Immutable state — selection + undo/redo stacks
        editor_state_history.dart    applyEdit, undo, redo extensions
        editor_snapshot.dart         Snapshot for undo stack entries
      domain/
        editor_actions.dart          All edit operations as EditorState extensions
      presentation/
        editor_shell_screen.dart     Full editor UI
        widgets/symbol_palette.dart  Draggable note/rest palette
        widgets/playback_controls_bar.dart  Play/pause/stop + BPM slider
    musicXML/                        Import pipeline
      musicxml_importer.dart         File pick + read + decompress
      musicxml_parser_service.dart   XML parse + validate
      musicxml_validator_service.dart Structural validation
      musicxml_score_converter.dart  XML → ScoreModel
    pdf/
      pdf_score_renderer.dart        Programmatic PDF renderer (replicates CustomPainter logic)
      pdf_export_service.dart        exportToDevice(Score) → system save dialog via file_picker
    musicxml_inspector/              Dev tool — MusicXML inspector screen
    detection_inspector/             Dev tool — Detection pipeline inspector

  core/
    utils/
      export_file_name.dart          Shared `safeExportFileName(title)` used by both XML and PDF export

assets/
  models/best_int8.tflite            YOLO model — 640×640 int8 quantized
  fonts/                             MaturaMTScriptCapitals
  images/                            notevision.png logo
  soundfonts/piano.sf2               GM SF2 soundfont for MIDI playback (not committed — see README.txt)

test/
  musicxml_testfiles/                7 XML test files (valid, invalid, edge cases)
  features/                          Unit + widget tests per feature
  core/
    services/
      playback_converter_test.dart   37 unit tests — noteToMidi, durationMs, scaledDuration, buildEvents
    utils/
      export_file_name_test.dart     10 unit tests — safeExportFileName edge cases
```

---

## Design System

All screens use the same dark theme. Never use light colors unless it is a notation canvas.

| Token | Value | Use |
|-------|-------|-----|
| Background | `0xFF0D0D0D` | Screen backgrounds |
| Surface | `0xFF1A1A1A` | Cards, panels, bottom sheets |
| Surface Alt | `0xFF161616` | Nested surfaces |
| Border | `0xFF2C2C2C` | All borders and dividers |
| Accent | `0xFFD4A96A` | Primary actions, highlights, selected state |
| Text Primary | `0xFFFFFFFF` | Main text |
| Text Secondary | `0xFF8A8A8A` | Subtitles, labels, hints |

---

## Key Decisions — Locked In

These are final unless explicitly changed:

- **Model input size:** 640×640 int8 — model is `assets/models/best_int8.tflite`
- **Tiling strategy:** No tiling — full image always stretched to 640×640 (no letterbox, no stave-based cropping). Model was trained on full-page stretches.
- **Staff detection:** Two sources merged — model `combStaff` detections (preferred) + `HorizontalProjectionStaffDetector` supplement + `SyntheticStaffBuilder` fallback. `SyntheticStaffBuilder` uses notehead Y distribution to estimate staff geometry when no staves detected.
- **Notation renderer:** CustomPainter — not a text list, not an SVG library
- **Undo/redo:** Whole-state snapshot, max 50 entries, new edit clears redo stack
- **Insert default:** C4 quarter note / quarter rest, appended to end of selected measure, auto-selected after insert — only via drag-from-palette. The INSERT inspector button group was removed (redundant with drag-drop). `insertNoteAfterSelection()` / `insertRestAfterSelection()` still exist in `EditorActions` for future use.
- **Drag insert:** LongPressDraggable from palette → DragTarget on staff. Drop Y → pitch via PitchCalculator. Drop X → insert index.
- **PDF export:** `pdf` package with programmatic Canvas drawing — replicates CustomPainter logic. `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled.
- **MusicXML export:** `xml` package, valid MusicXML 3.1. `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled.
- **Audio playback:** `flutter_midi_pro` — synthesizes from Note step+octave+duration directly. Requires `assets/soundfonts/piano.sf2` (any standard GM SF2 file, not committed). After adding the file run `flutter clean && flutter pub get` then do a full restart (not hot reload) to rebundle assets.
- **Save/load:** JSON files in app documents directory via path_provider. Project index in shared_preferences.
- **Export filename:** shared `safeExportFileName(title)` in `lib/core/utils/export_file_name.dart`.
- **Delete symbol:** drag-to-trash gesture — drag a symbol to the trash zone in `EditorShellScreen`; no separate delete button. In portrait mode the trash zone overlays the inspector bar (`bottom: 0, height: _kInspectorBarHeight`) while a drag is active so it stays reachable at the bottom edge.
- **Portrait inspector:** `_BottomInspectorBar` — a 56 px horizontal bar (`_kInspectorBarHeight = 56.0`) above `PlaybackControlsBar` with four tab buttons (PITCH, ACCIDENTAL, DURATION, MEASURE). Tapping a tab opens a popup that floats upward; action buttons keep the popup open so the user can press repeatedly (e.g. Up/Down multiple times). Close by re-tapping the same tab or tapping the canvas. Landscape keeps the original side-panel layout.
- **In-project scan:** "Scan Page" icon button (`Icons.add_photo_alternate_rounded`) in `_EditorHeader`, disabled during playback. Tapping shows a bottom sheet (Camera / Gallery), picks image, then pushes `ScanScreenProvider(appendMode: true)`. On "Continue", `ScanScreen` pops with the scanned `Score` instead of pushing `EditorShellScreen`. The editor merges parts by index (min of current vs scanned part count), renumbers all measures, pushes to undo stack, and jumps to the last page.
- **Scan preferences:** `ScanPreferencesService` stores two booleans in SharedPreferences (`scan_skip_preview`, `scan_skip_review`, both default `false`). Toggles live in a "SCAN SETTINGS" section at the bottom of `ProfileStatsScreen`. Skip-preview skips the image preview in `CaptureScreen` and goes straight to scanning. Skip-review auto-advances past the detection results screen in `ScanScreen` when detections are found (guarded by `_autoNavigated` flag to prevent double-fire).
- **Playback lock:** all editor interactions (symbol tap, drag, palette, insert mode, inspector tiles, undo/redo) are disabled when `PlaybackStatus.playing`. Pan/zoom is unaffected. `paused` leaves interactions enabled so the user can edit between playback sessions.
- **Playback page auto-advance:** `positionStream` from `PlaybackService` updates `_currentPageIndex` in `_EditorShellScreenState` when `measureIndex ~/ _kMeasuresPerPage` changes. Viewport zoom/fit is NOT reset on playback-driven page changes (only on manual navigation).
- **Smooth page transition:** `AnimatedSwitcher` (250ms crossfade) wraps the white-sheet `Container` inside `InteractiveViewer`, keyed by `pageFirstMeasure`. Triggers on both manual and playback-driven page changes.
- **Cross-measure/part drag reorder:** `moveSymbolToDest()` in `editor_actions.dart` — same-measure delegates to `reorderSymbol`; cross-measure deletes from source + inserts at destination; cross-part supported.
- **Collection = project list:** `CollectionScreen` owns both the scan history and the saved project list. `ProjectListScreen` was deleted; `/projects` route removed.
- **Analytics:** Local only — scans, edits, exports, playbacks as integers in shared_preferences. No backend.
- **Username:** Name + profile photo. First-launch onboarding. Stored locally.
- **App is fully offline:** No network calls, no auth, no backend, ever.
- **noteheadBlack fallback:** When YOLO misses the stem of a black notehead, the note is assumed quarter rather than dropped. Priority: (1) stem + flag/beam → eighth, (2) stem only → quarter, (3) beam but no stem → eighth, (4) no stem/beam → quarter.
- **Multi-page rendering:** Editor splits the score into pages of `_kMeasuresPerPage = 9` measures (3 rows × 3). `_currentPageIndex` lives in `_EditorShellScreenState` (not `EditorState`) so undo/redo don't change pages. `ScoreNotationViewer` accepts `firstMeasureIndex` + `pageMeasureCount` to slice measures; `_NotationAreaState` translates all interaction indices (tap, insert, drag, drop) between page-relative and absolute. Measure prev/next navigation auto-switches pages at boundaries.

---

## EditorState — How It Works

`EditorState` is immutable. Every edit returns a new instance via `copyWith`.

```dart
// Key fields
Score score                    // Current ScoreModel
int? selectedPartIndex         // Which part is selected
int? selectedMeasureIndex      // Which measure is selected
int? selectedSymbolIndex       // Which symbol index is selected
ScoreSymbol? selectedSymbol    // The actual selected symbol object
List<EditorSnapshot> undoStack // Max 50 entries
List<EditorSnapshot> redoStack // Cleared on new edit
bool hasUnsavedChanges         // Set true on edit, false after save

// Key operations (all in editor_actions.dart)
applyEdit(score, ...)               // Push to undo stack + update state
undo()                              // Pop undo stack, push to redo stack
redo()                              // Pop redo stack, push to undo stack
moveSelectedSymbolUp/Down()         // Diatonic pitch move, preserves alter
setSelectedDuration(spec)           // No-op if same duration
setSelectedNoteAccidental(int?)     // null=none 1=♯ -1=♭ 0=♮; no-op for rests/same value
deleteSelectedSymbol()              // Keeps measure context for re-insert
insertNoteAfterSelection()          // Appends C4 quarter, auto-selects (no UI button — used by drag-palette)
insertRestAfterSelection()          // Appends quarter rest, auto-selects (no UI button — used by drag-palette)
reorderSymbolWithinMeasure()        // Cannot cross measure boundary (legacy path; prefer moveSymbolToDest)
moveSelectedSymbolToMeasureOffset() // Move symbol to adjacent measure
moveSymbolToDest(fromPart, fromMeasure, fromSymbol, toPart, toMeasure, toSymbol)
                                    // Cross-measure/part drag reorder; same-measure delegates to reorderSymbol
addMeasureAfterSelected()           // Inserts empty measure after selection in all parts simultaneously
deleteSelectedMeasureIfEmpty()      // Guards: count > 1 AND symbols.isEmpty
```

---

## ScoreModel — Structure

```dart
Score
  id: String
  title: String
  composer: String
  parts: List<Part>
    Part
      id: String
      name: String
      measures: List<Measure>
        Measure
          number: int
          clef: Clef?           sign (G/F), line
          timeSignature: TS?    beats, beatType
          keySignature: KS?     fifths (-7 to +7)
          symbols: List<ScoreSymbol>
            Note
              step: String      C D E F G A B
              octave: int
              alter: int?       -2=𝄫 -1=♭ 0=♮ 1=♯ 2=𝄪 null=none
              duration: int     divisions
              type: String      whole half quarter eighth sixteenth
              voice: int?
              staff: int?
            Rest
              duration: int
              type: String
              voice: int?
              staff: int?

// Score helpers (all return new Score — immutable)
getSymbolAt(partIndex, measureIndex, symbolIndex)
replaceSymbolAt(partIndex, measureIndex, symbolIndex, newSymbol)
deleteSymbolAt(partIndex, measureIndex, symbolIndex)
insertSymbolAt(partIndex, measureIndex, symbolIndex, symbol)
reorderSymbol(partIndex, measureIndex, fromIndex, toIndex)
insertMeasureAfterInAllParts(measureIndex)   // renumbers all measures 1-indexed
deleteMeasureFromAllParts(measureIndex)      // renumbers all measures 1-indexed
```

---

## Reconstruction — What Works vs What Doesn't

| Feature | Status |
|---------|--------|
| Single treble clef stave | ✅ Works |
| Multi-stave (one Part per staff) | ✅ Works |
| Staff assignment | ✅ Works — model combStaff detections preferred, projector supplement, synthetic fallback |
| Measure grouping from barlines | ✅ Works |
| Note reconstruction (whole/half/quarter/eighth/sixteenth) | ✅ Works — noteheadBlack without stem assumed quarter |
| Rest reconstruction (whole/half/quarter/eighth/sixteenth) | ✅ Works |
| Pitch calculation from staff position | ✅ Works — treble + bass clef both supported |
| Stem/flag/beam association | ✅ Works |
| Key signature | ✅ Works — accidental cluster count → fifths |
| Time signature | ✅ Works — digit pair + common/cut |
| Accidentals on individual notes | ✅ Works — proximity match to notehead |
| Beamed eighth notes | ✅ Works |
| Bass clef (fClef) pitch reconstruction | ✅ Works |
| SyntheticStaffBuilder fallback | ✅ Works — estimates staff from notehead Y distribution |
| Grand staff | ❌ Not supported |
| Chords | ❌ Not supported |
| Ties, slurs, tuplets | ❌ Not supported |

---

## Known Bugs — Not Yet Ticketed

All previously tracked bugs (B1–B5) have been fixed. No open bugs.

---

## Ticket Status

### Sprints 1–9 ✅ All Complete
Sprints 1–9 (tickets 1–93) are fully shipped. Sprint 10 is the active sprint (tickets being decided).

### Sprint 10 🔄 In Progress
| # | Ticket | Owner | Status |
|---|--------|-------|--------|
| 94 | Collection Screen: Remove Redundant Add Button | Boleche | ✅ Done (sprint10-quick-fixes) |
| 95 | Editor: Add Multi-Page Score Support | Canete | ✅ Done (sprint10-quick-fixes) |
| 96 | Editor: Replace Measure Navigation with Page Navigation | Boleche | ✅ Done (sprint10-quick-fixes) |
| 97 | Editor: Score Page Tab Bar | Boleche | ✅ Done (sprint10-quick-fixes) |
| 98 | Editor: Redesign Tempo Control | Boleche | ✅ Done (sprint10-quick-fixes) |
| 99 | Editor: In-Project Scan (Add a New Page from the Editor) | Canete | ✅ Done (sprint10-quick-fixes) |
| 100 | Settings: Independent Scan Preview/Review Toggles | Canete | ✅ Done (sprint10-quick-fixes) |
| 101 | Replace Burger Menu Button with Profile Icon as Drawer Trigger | Boleche | ✅ Done (sprint10-quick-fixes) |
| 102 | Editor: Smooth Page Transition During Playback | Canete | ✅ Done (sprint10-quick-fixes) |
| 103 | Editor: Full-Screen Error State on Save Failure | Canete | ✅ Done (sprint10-quick-fixes) |
| 104 | Editor: Playback Auto-Advances Page | Canete | ✅ Done (sprint10-quick-fixes) |

### Sprint 11 — Reconstruction Improvements
| # | Ticket | Owner | Status |
|---|--------|-------|--------|
| 105 | Dotted Note/Rest Reconstruction | Canete | ⏳ Not started |
| 106 | Chord Reconstruction | Canete | ⏳ Not started |
| 107 | Repeat Barline Detection | Canete | ⏳ Not started |
| 108 | Double Whole Note Support | Canete | ⏳ Not started |
| 109 | Ledger Line Pitch Accuracy | Canete | ⏳ Not started |
| 110 | Per-Class Detection Confidence Thresholds | Canete | ⏳ Not started |
| 111 | Editor Header: Collapse Action Buttons into Overflow Menu | Boleche | ⏳ Not started |
| 112 | Score Genre/Label Classification | Canete | ⏳ Not started |

---

## What the App Cannot Do (Current Limits)

These are current limitations, not hard ceilings — going beyond them is fine if it makes the app better.

- Bass clef rendering ✅ done in editor and PDF export; alto clef, tenor clef still unsupported
- Grand staff (two staves, piano LH+RH)
- Chords (multiple notes on one stem)
- Ties, slurs, tuplets, dotted rhythms
- Sixteenth notes or smaller
- Grace notes, ornaments
- Dynamics, articulations, tempo markings
- Repeat signs, D.C., D.S., coda
- Multiple voices on one staff
- Lyrics
- Handwritten music
- Cloud sync, accounts, collaboration
- Any network call of any kind

---

## How to Use This File

At the start of a Claude session paste this file or reference it.
Claude can then ask you what ticket or feature to work on without needing the full codebase in context.
Update this file whenever:
- A ticket status changes
- A new decision is locked in
- A bug is found or fixed
- A new ticket is added
- A scope change happens

Do not let this file get stale — an outdated CLAUDE.md is worse than no CLAUDE.md.

claude and I can update this from time to time when changes are final

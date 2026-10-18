# Note Vision — Project Context

> Feed this file to Claude at the start of every session.
> Keep it updated as decisions change, tickets are added, or bugs are found.
> It is intentionally concise — specs live in Jira, code lives in the repo.

---

## What This App Is

Note Vision is a fully offline Flutter mobile app for Optical Music Recognition (OMR).
The user photographs handwritten sheet music, the app detects musical symbols using an on-device
TFLite YOLO model, reconstructs the symbols into a digital score, lets the user correct
mistakes in an editor, then exports or plays back the result. No internet. No server. Everything on-device.

**Target users:** Music students, teachers, musicians who want to digitize handwritten scores quickly.

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
| ML model | YOLO26n at 960×960 — 24 handwritten symbol classes (model B6): clefs, 5 note values, 5 rests, beam, sharp/flat/natural, time-sig digits 2/3/4/6/8, C, cut time, augmentation dot |
| Genre model | LSTM (`assets/models/genre_lstm.tflite`, 2.4 MB, 4-seed average): waltz / kundiman / jazz / other from the melody of all parts in reading order (first 320 notes); input [1,64,22]: step, rest, length, place in bar, meter, plus scale degree (12) and minor flag from Krumhansl–Schmuckler (`GenreModel.keyOf`); trained in the data project (`scripts/genre_train.py`, v3: + Weimar Jazz DB solos, Essen folk songs, PDMX jazz/waltz/other; kundiman from synthetic melodies (`kundiman_gen.py` + `trait_kundiman`, from published descriptions of the genre) plus 14 real transcriptions, 4 more held out for validation; 4-fold cross-validation over the 14: 13/14 whole songs, 12/14 on 40-note pieces, 0.5% of non-kundiman called kundiman with the app's logic) |
| Image processing | image 4.8.0 |
| XML parsing | xml 6.5.0 |
| File picking | file_picker 8.1.2 |
| Camera / gallery | image_picker 1.1.2 (system camera and gallery) |
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
2. Staff Line Detection (projector)
   HorizontalProjectionStaffDetector — level, evenly ruled staves only; on
   handwriting it is a last resort (see step 3)
        ↓
3. Symbol Detection + staves + barlines
   TfliteSymbolDetector — full image stretched to 960×960 (no tiling/letterbox)
   YOLO26n FP32 LiteRT, NCHW input, raw [1,28,18900] output, Dart NMS, confidence 0.40 (rests 0.30)
   Each note box is one whole symbol (head+stem+flag); it is shrunk to its notehead
   (for pitch), the model's whole box is kept in metadata['fullBox'] and the note
   value in metadata['noteType']. Beam boxes turn beamed quarters into 8ths/16ths
   and mark them metadata['beamed'], so the editor draws them beamed.
   Staves, in order of preference:
     StaffLineTracer — follows each drawn line across the page (hand-ruled, sloped,
       bent staves); each detected clef picks the five lines it sits on.
       DetectedStaff.offsetAt(x) carries the slope/bend; pitch, staff assignment,
       time-sig digits and the overlay all read the staff where the symbol stands.
     clef-sized level staff (handwritten proportions: G clef 1.48 staves tall, F 0.85)
     projector staves where there is no clef; cluster/synthetic fallbacks after that
   BarlineFinder — thin full-staff-height strokes that are not inside a clef or
     stemmed-note box and stop at the staff → DetectionResult.barlines
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
                                     Clef, KeySignature, TimeSignature, ScoreSymbol,
                                     note_value.dart (quarterLength: timing from type + dots)
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
      genre_model.dart               Genre LSTM: melody → features → waltz/kundiman/jazz/other
      score_classifier.dart          Genre label shown in the app (model, then 3-genre rules)
      playback_service.dart          Singleton MIDI playback service via flutter_midi_pro

  features/
    landing/                         LandingScreen — entry point
    collection/                      CollectionScreen — saved score grid + project list (merged)
    capture/                         CaptureScreen — camera + gallery
    scan/                            ScanScreen + ScanViewModel — pipeline orchestrator
    preprocessing/                   BasicImagePreprocessor, StaffLineTracer, BarlineFinder
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
        widgets/playback_controls_bar.dart  Responsive transport, measure scrubber, BPM buttons
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
  models/best.tflite                 YOLO26n model B6 — 960×960 FP32, 24 classes
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

- **Model:** `assets/models/best.tflite` — YOLO26n model B6, 960×960 FP32 LiteRT, 24 handwritten classes, trained on stretched grayscale images (data project and training notebooks live outside this repo)
- **Tiling strategy:** No tiling — full image always stretched to 960×960 (no letterbox, no stave-based cropping). Model was trained on full-page stretches.
- **Staff detection:** `StaffLineTracer` per clef (preferred) → clef-sized level staff → `HorizontalProjectionStaffDetector` where no clef → cluster / `SyntheticStaffBuilder` fallbacks. A staff with no clef of its own is read in the clef of the nearest staff above (else below).
- **Bars:** split at barlines found by `BarlineFinder`; a staff with none falls back to beat counting. `ScoreBuilder` pads parts to equal measure counts because the editor pages by measure index.
- **Notation renderer:** CustomPainter — not a text list, not an SVG library. Editor and PDF follow the same rules: the key signature starts every row; the time signature shows on a page's first measure and wherever it changes (before the row's opening barline when the key leaves room, else inside the measure, whose notes move right; `ScoreNotationMetrics.timeSignatureInMeasure`). Flags are solid and point right on up and down stems; beamed eighths and sixteenths are drawn with beams (a chord tone neither joins nor ends a group).
- **Undo/redo:** Whole-state snapshot, max 50 entries, new edit clears redo stack
- **Note values:** the editor offers the scanner's ten values: whole, half, quarter, eighth and sixteenth notes and rests (palette, DURATION tab, drawing in editor and PDF). A symbol's stored `duration` counts 2 divisions per quarter, which cannot hold a sixteenth or a dotted eighth, so all timing (playback, MusicXML `<duration>`, measure-full checks, genre model) uses `quarterLength(type, dots, duration)` from `lib/core/models/note_value.dart`. Chord tones take no time in a measure.
- **Hidden, not removed:** `AppFeatures` (`lib/core/config/app_features.dart`) switches off features the presentation build does not show: `classroomWorkflow` (teacher/student), `legacyScoreLabels` (the old rule labels), `cClefs` (alto/tenor clef tiles; the scanner reads G and F clefs only).
- **Insert default:** C4 quarter note / quarter rest, appended to end of selected measure, auto-selected after insert — only via drag-from-palette. The INSERT inspector button group was removed (redundant with drag-drop). `insertNoteAfterSelection()` / `insertRestAfterSelection()` still exist in `EditorActions` for future use.
- **Drag insert:** LongPressDraggable from palette → DragTarget on staff. Drop Y → pitch via PitchCalculator. Drop X → insert index.
- **PDF export:** `pdf` package with programmatic Canvas drawing — replicates CustomPainter logic. `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled.
- **MusicXML export:** `xml` package, valid MusicXML 3.1. `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled. Writes 8 divisions per quarter with each `<duration>` from the written type and dots, and spells a sixteenth `16th`. Exports `<print new-page="yes">` and `<print new-system="yes">` from `Measure.startsNewPage` / `startsNewSystem`. Exports `<beam>` elements (begin/continue/end) for beamed notes.
- **MusicXML import:** `ImportScoreScreen` uses `MusicXmlImporter`: one system picker showing all files (a filtered picker greys out .musicxml/.mxl on Android), then the extension is checked; reads .xml, .musicxml and .mxl (the file `META-INF/container.xml` names), UTF-8, UTF-16 or Latin-1. Reads `<print new-page="yes">` → `Measure.startsNewPage` and `<print new-system="yes">` → `Measure.startsNewSystem`. Normalizes `<duration>` values from any `<divisions>` setting to the internal 2-divisions-per-quarter convention. A note or rest without `<type>`, and every whole-bar rest (`<rest measure="yes"/>`), takes its value from its duration (a 3/4 bar rest becomes a dotted half). A `16th` is stored as `sixteenth`, as scans write it. A note with any `<beam>` is `beamed`; since that is one bool per note, beam groups that touch are drawn and exported as one group. The preview shows page 1 as the editor lays it out (`ScorePageThumbnail`).
- **Imported layout preservation:** Explicit page breaks (`startsNewPage`) start a new editor page; scores without them fall back to the 4×5 grid. System breaks (`startsNewSystem`) are kept through edits and written back on export, but the editor grid does not break rows at them. Reflow (resetting breaks) is deferred to Milestone 5.
- **Audio playback:** `flutter_midi_pro` — synthesizes from Note step+octave+duration directly. Requires `assets/soundfonts/piano.sf2` (any standard GM SF2 file, not committed). After adding the file run `flutter clean && flutter pub get` then do a full restart (not hot reload) to rebundle assets.
- **Score label (genre):** the app shows only Waltz, Kundiman or Jazz (null for a score without notes): on score cards, in the editor header (worked out 600 ms after edits stop) and on the scan result screen. `ScoreClassifier.classify` asks `GenreModel` (LSTM, loaded in `main`) first and uses its answer when at least 0.7 sure of one of the three. Otherwise (it says "other", is unsure, has under 16 notes, or is not loaded) `classifyByRules` picks one of the three (a rule Kundiman also needs the model's kundiman ≥ `minRuleKundiman` 0.4 when the model ran, else Waltz; `ScoreClassifier.decide` is the testable core): not triple time → Jazz; triple time (3, 6 or 9 beats) → Kundiman when the first half of the melody is in a minor key (Krumhansl–Schmuckler), else Waltz. The old labels live on in `classifyByLegacyRules` behind `AppFeatures.legacyScoreLabels`. `GenreModel.features` must match `features()` in the data project's genre_train.py.
- **Review & Correct (paper Objective 3):** the editor has a visible review button and an automatic reminder after scans; the overflow menu also retains "Check Notation". `NotationReviewPanel` stays beside the score on wide screens and below it on phones (resizable). Selecting a finding focuses its measure; the canvas remains pannable/zoomable, with editing available via "Edit manually". Each suggested change requires a current/proposed preview; batch review applies only explicitly selected, still-valid suggestions as one undo step. Dependent suggestions are rechecked and omitted when their context changes. `NotationReviewService` assigns stable measure/symbol IDs, records applied/kept decisions, rejects stale previews, and supports conflict-checked restore from History. Decisions and scan evidence live in `Score.reviewHistory` / `sourcePages`, travel through project save/export, and participate in undo/redo. Original scan crops come from normalized symbol bounds retained by the mapper; `ScoreSourceService` compresses an orientation-corrected page once per scan, fully offline. Older projects and MusicXML work without source images. Passage audition uses the same tempo for current/proposed notation, stops at the affected range, and cancels pending playback when review closes. The checker still covers uncertain recognition, missing components, redundant accidentals, beat totals (pickup exempt), and meter mismatches; mathematical consistency is presented as a suggestion requiring musical judgment. Tests: `notation_review_service_test.dart`, `score_source_service_test.dart`, `review_playback_test.dart`, `notation_review_workflow_test.dart`. Set `NV_REVIEW_SCREENSHOTS=/tmp/note-vision-review-screenshots` when running the workflow test to render phone/tablet comparisons.
- **Save/load:** JSON files in app documents directory via path_provider. Project index in shared_preferences. The editor compares the current score with the last saved snapshot, so undo/redo and edits during an asynchronous save retain an accurate Unsaved indicator. Save is disabled while saving, with visible progress.
- **Export filename:** shared `safeExportFileName(title)` in `lib/core/utils/export_file_name.dart`.
- **Delete symbol:** use Delete in the PITCH tool group, or drag a symbol to the trash zone in `EditorShellScreen`. In portrait mode the trash zone overlays the inspector bar (`bottom: 0, height: _kInspectorBarHeight`) while a drag is active so it stays reachable at the bottom edge.
- **Editor layout and controls:** narrow headers put Review, Undo/Redo and Save on a second row, retaining title space and 44 px touch targets. Tool tile widths follow text scaling. Pitch controls require a note, and duration/dot controls reflect measure capacity. Symbol and blank-measure taps both update the editing context. The palette hides while a symbol is selected; Insert reveals it and Done exits insertion. Tool tabs, insertion mode and palette items expose screen-reader activation actions. The initial canvas fit uses actual notation height; selected measures focus inside the space available between overlays. Zoom buttons clamp to 15–500%.
- **Portrait inspector:** `_BottomInspectorBar` — a 56 px horizontal bar (`_kInspectorBarHeight = 56.0`) above `PlaybackControlsBar` with six tab buttons (Pitch, Accidental, Clef, Time, Duration, Measure; title case so they fit at 10 px). TIME sets 2/4, 3/4, 4/4, 2/2, 3/8 or 6/8 on the selected measure in every part. Tapping a tab opens a popup that floats upward; action buttons keep the popup open so the user can press repeatedly (e.g. Up/Down multiple times). Close by re-tapping the same tab or tapping the canvas. Landscape keeps the original side-panel layout.
- **In-project scan:** "Scan Page" icon button (`Icons.add_photo_alternate_rounded`) in `_EditorHeader`, disabled during playback. Tapping shows a bottom sheet (Camera / Gallery), picks image, then pushes `ScanScreenProvider(appendMode: true)`. On "Continue", `ScanScreen` pops with the scanned `Score` instead of pushing `EditorShellScreen`. The editor merges parts by index (min of current vs scanned part count), renumbers all measures, pushes to undo stack, and jumps to the last page.
- **Scan preferences:** `ScanPreferencesService` stores two booleans in SharedPreferences (`scan_skip_preview`, `scan_skip_review`, both default `false`). Toggles live in a "SCAN SETTINGS" section at the bottom of `ProfileStatsScreen`. Skip-preview skips the image preview in `CaptureScreen` and goes straight to scanning. Skip-review auto-advances past the detection results screen in `ScanScreen` when detections are found (guarded by `_autoNavigated` flag to prevent double-fire).
- **Playback controls:** `PlaybackControlsBar` uses the editor's injected service and a native accessible measure slider, with 48 px transport/tempo targets. Small screens and large text use two rows. The scrubber follows actual staff lengths. Seeking while stopped or paused cues silently; Resume rebuilds events from current edits while retaining the cued symbol when its ID survives. Loading can be cancelled with Stop, and errors expose Retry. `editor_controls_test.dart` covers layouts, semantics, transport, and save state; set `NV_EDITOR_SCREENSHOTS=/tmp/note-vision-editor-controls` to render snapshots.
- **Playback lock:** all editor interactions (symbol tap, drag, palette, insert mode, inspector tiles, undo/redo, metadata) are disabled during loading and `PlaybackStatus.playing`. Pan/zoom is unaffected. `paused` leaves interactions enabled so the user can edit between playback sessions.
- **Playback page auto-advance:** `positionStream` from `PlaybackService` updates `_currentPageIndex` in `_EditorShellScreenState` when the page index derived from `EditorLayoutPolicy` changes. Viewport zoom/fit is NOT reset on playback-driven page changes (only on manual navigation).
- **Smooth page transition:** `AnimatedSwitcher` (250ms crossfade) wraps the white-sheet `Container` inside `InteractiveViewer`, keyed by `pageFirstMeasure`. Triggers on both manual and playback-driven page changes.
- **Cross-measure/part drag reorder:** `moveSymbolToDest()` in `editor_actions.dart` — same-measure delegates to `reorderSymbol`; cross-measure deletes from source + inserts at destination; cross-part supported.
- **Collection = project list:** `CollectionScreen` owns both the scan history and the saved project list. `ProjectListScreen` was deleted; `/projects` route removed.
- **Analytics:** Local only — scans, edits, exports, playbacks as integers in shared_preferences. No backend.
- **Username:** Name + profile photo. First-launch onboarding. Stored locally.
- **App is fully offline:** No network calls, no auth, no backend, ever.
- **noteheadBlack fallback:** When YOLO misses the stem of a black notehead, the note is assumed quarter rather than dropped. Priority: (1) stem + flag/beam → eighth, (2) stem only → quarter, (3) beam but no stem → eighth, (4) no stem/beam → quarter.
- **Multi-page rendering:** Editor splits the score into pages via `EditorLayoutPolicy` — default is `EditorLayoutPolicy.standard` (4 measures per row × 5 rows = 20 measures per page, changed from the original 3×3=9 during Milestone 3). `_currentPageIndex` lives in `_EditorShellScreenState` (not `EditorState`) so undo/redo don't change pages. `ScoreNotationViewer` accepts `firstMeasureIndex` + `pageMeasureCount` to slice measures; `_NotationAreaState` translates all interaction indices (tap, insert, drag, drop) between page-relative and absolute. Measure prev/next navigation auto-switches pages at boundaries. Scores with explicit `startsNewPage` breaks on measures bypass the fixed grid entirely.

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
| Staff assignment | ✅ Works — traced staves (follow slope/bend), clef-sized, projector and synthetic fallbacks |
| Measure grouping from barlines | ✅ Works — barlines found in the image; one drawn against a note is taken for its stem and missed |
| Note reconstruction (whole/half/quarter/eighth/sixteenth) | ✅ Works — noteheadBlack without stem assumed quarter |
| Rest reconstruction (whole/half/quarter/eighth/sixteenth) | ✅ Works |
| Pitch calculation from staff position | ✅ Works — treble + bass clef both supported |
| Stem/flag/beam association | ✅ Works |
| Key signature | ✅ Works — accidental cluster count → fifths |
| Time signature | ✅ Works — digit pair + common/cut; editable in the editor's TIME tab |
| Accidentals on individual notes | ✅ Works — proximity match to notehead |
| Beamed eighth notes | ✅ Works |
| Bass clef (fClef) pitch reconstruction | ✅ Works |
| SyntheticStaffBuilder fallback | ✅ Works — estimates staff from notehead Y distribution |
| Grand staff | ❌ Not supported |
| Chords | ❌ Not detected — the model reads two heads on one stem as one note |
| Ties, slurs, tuplets | ❌ Not supported |

---

## Known Bugs — Not Yet Ticketed

All previously tracked bugs (B1–B5) have been fixed. No open bugs.

---

## Ticket Status

### Sprints 1–10 ✅ All Complete
Sprints 1–10 (tickets 1–104) are fully shipped.

### Sprint 11 ✅ All Complete
| # | Ticket | Owner | Status |
|---|--------|-------|--------|
| 105 | Dotted Note/Rest Reconstruction | Canete | ✅ Done (milestone-3-layout-foundation) |
| 106 | Chord Reconstruction | Canete | ✅ Done (milestone-3-layout-foundation) |
| 107 | Repeat Barline Detection | Canete | ✅ Done (milestone-3-layout-foundation) |
| 108 | Double Whole Note Support | Canete | ✅ Done (milestone-3-layout-foundation) |
| 109 | Ledger Line Pitch Accuracy | Canete | ✅ Done (milestone-3-layout-foundation) |
| 110 | Per-Class Detection Confidence Thresholds | Canete | ✅ Done (milestone-3-layout-foundation) |
| 111 | Editor Header: Collapse Action Buttons into Overflow Menu | Boleche | ✅ Done (milestone-3-layout-foundation) |
| 112 | Score Genre/Label Classification | Canete | ✅ Done (milestone-3-layout-foundation) |

### Sprint 12 — Editor Polish & Export Quality
| # | Ticket | Owner | Status |
|---|--------|-------|--------|
| 113 | Editor: Layout grid change (4×5 = 20 measures/page) | Canete | ✅ Done (milestone-3-layout-foundation) |
| 114 | Editor: Add Measure always appends to end | Canete | ✅ Done (milestone-3-layout-foundation) |
| 115 | Editor: Clef change recalculates all note pitches (part-level) | Canete | ✅ Done (milestone-3-layout-foundation) |
| 116 | MusicXML: Import/export startsNewSystem breaks | Canete | ✅ Done (milestone-3-layout-foundation) |
| 117 | MusicXML: Import divisions normalization (any source divisions) | Canete | ✅ Done (milestone-3-layout-foundation) |
| 118 | MusicXML: Export beam elements (begin/continue/end) | Canete | ✅ Done (milestone-3-layout-foundation) |

---

## What the App Cannot Do (Current Limits)

These are current limitations, not hard ceilings — going beyond them is fine if it makes the app better.

- Bass clef rendering ✅ done in editor and PDF export; alto and tenor clefs are drawn but hidden from the editor (`AppFeatures.cClefs`) because the scanner cannot read them
- Grand staff (two staves, piano LH+RH)
- Chords: the model has no class for a second notehead on a stem, so a scanned chord becomes one note
- Dotted note/rest rhythms ✅ reconstructed from scan
- Repeat barlines ✅ detected and exported to MusicXML
- Ties, slurs, tuplets
- 32nd notes or smaller
- Grace notes, ornaments
- Dynamics, articulations, tempo markings
- D.C., D.S., coda
- Multiple voices on one staff
- Lyrics
- Printed (engraved) music — the model is trained on handwriting only
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

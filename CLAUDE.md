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
| PDF export | pdf package (Sprint 7) |
| Audio playback | flutter_midi_pro (Sprint 7) |
| File sharing | share_plus (Sprint 6+) |
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
6. Export / Playback  [Sprint 7]
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
        editor_actions.dart          All edit operations as EditorState extensions (incl. cross-measure/part moveSymbolToDest)
      presentation/
        editor_shell_screen.dart     Full editor UI
        widgets/symbol_palette.dart  Draggable note/rest palette (Sprint 6)
        widgets/playback_controls_bar.dart  Play/pause/stop + BPM slider (Sprint 7)
    musicXML/                        Import pipeline
      musicxml_importer.dart         File pick + read + decompress
      musicxml_parser_service.dart   XML parse + validate
      musicxml_validator_service.dart Structural validation
      musicxml_score_converter.dart  XML → ScoreModel
    musicxml_inspector/              Dev tool — MusicXML inspector screen
    detection_inspector/             Dev tool — Detection pipeline inspector

  core/
    utils/
      export_file_name.dart          Shared `safeExportFileName(title)` used by both XML and PDF export

assets/
  models/best_int8.tflite            YOLO model — 640×640 int8 quantized (replaces omr_model.tflite)
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

- **Model input size:** 640×640 int8 — model is `assets/models/best_int8.tflite` (ticket 37 done)
- **Tiling strategy:** No tiling — full image always stretched to 640×640 (no letterbox, no stave-based cropping). Decided BGC-57: model was trained on full-page stretches.
- **Staff detection:** Two sources merged — model `combStaff` detections (preferred) + `HorizontalProjectionStaffDetector` supplement + `SyntheticStaffBuilder` fallback. `SyntheticStaffBuilder` uses notehead Y distribution to estimate staff geometry when no staves detected.
- **Notation renderer:** CustomPainter — not a text list, not an SVG library
- **Undo/redo:** Whole-state snapshot, max 50 entries, new edit clears redo stack
- **Insert default:** C4 quarter note / quarter rest, appended to end of selected measure, auto-selected after insert — only via drag-from-palette. The INSERT inspector button group was removed in Sprint 9 as a side task (redundant with drag-drop). `insertNoteAfterSelection()` / `insertRestAfterSelection()` still exist in `EditorActions` for future use.
- **Drag insert:** LongPressDraggable from palette → DragTarget on staff. Drop Y → pitch via PitchCalculator. Drop X → insert index.
- **PDF export:** `pdf` package with programmatic Canvas drawing — replicates CustomPainter logic
- **Audio playback:** `flutter_midi_pro` — synthesizes from Note step+octave+duration directly. Requires `assets/soundfonts/piano.sf2` (any standard GM SF2 file, not committed). After adding the file run `flutter clean && flutter pub get` then do a full restart (not hot reload) to rebundle assets.
- **Save/load:** JSON files in app documents directory via path_provider. Project index in shared_preferences.
- **MusicXML export:** `xml` package, valid MusicXML 3.1. `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled.
- **PDF export:** `pdf` package, `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled.
- **Export filename:** shared `safeExportFileName(title)` in `lib/core/utils/export_file_name.dart`.
- **Delete symbol:** drag-to-trash gesture — drag a symbol to the trash zone in `EditorShellScreen`; no separate delete button. In portrait mode the trash zone overlays the inspector bar (`bottom: 0, height: _kInspectorBarHeight`) while a drag is active so it stays reachable at the bottom edge.
- **Portrait inspector:** `_BottomInspectorBar` — a 56 px horizontal bar (`_kInspectorBarHeight = 56.0`) above `PlaybackControlsBar` with four tab buttons (PITCH, ACCIDENTAL, DURATION, MEASURE). Tapping a tab opens a popup that floats upward; action buttons keep the popup open so the user can press repeatedly (e.g. Up/Down multiple times). Close by re-tapping the same tab or tapping the canvas. Landscape keeps the original side-panel layout.
- **Cross-measure/part drag reorder:** `moveSymbolToDest()` in `editor_actions.dart` — same-measure delegates to `reorderSymbol`; cross-measure deletes from source + inserts at destination; cross-part supported.
- **Collection = project list:** `CollectionScreen` owns both the scan history and the saved project list. `ProjectListScreen` was deleted; `/projects` route removed.
- **Analytics:** Local only — scans, edits, exports, playbacks as integers in shared_preferences. No backend.
- **Username:** Name + profile photo. First-launch onboarding. Stored locally.
- **App is fully offline:** No network calls, no auth, no backend, ever.

---

## EditorState — How It Works

`EditorState` is immutable. Every edit returns a new instance via `copyWith`.

```dart
// Key fields
Score score                    // Current ScoreModel
int? selectedPartIndex         // Which part is selected (always 0 in Sprint 5)
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
```

---

## Reconstruction — What Works vs What Doesn't

| Feature | Status |
|---------|--------|
| Single treble clef stave | ✅ Works |
| Multi-stave (one Part per staff) | ✅ Works — BGC-57 |
| Staff assignment | ✅ Works — model combStaff detections preferred, projector supplement, synthetic fallback |
| Measure grouping from barlines | ✅ Works |
| Note reconstruction (whole/half/quarter/eighth/sixteenth) | ✅ Works — noteheadBlack without stem assumed quarter (stems frequently missed by model) |
| Rest reconstruction (whole/half/quarter/eighth/sixteenth) | ✅ Works — BGC-59 |
| Pitch calculation from staff position | ✅ Works — treble + bass clef both supported |
| Stem/flag/beam association | ✅ Works — BGC-59 beams |
| Key signature | ✅ Works — accidental cluster count → fifths — BGC-59 |
| Time signature | ✅ Works — digit pair + common/cut — BGC-59 |
| Accidentals on individual notes | ✅ Works — proximity match to notehead — BGC-59 |
| Beamed eighth notes | ✅ Works — hasBeam flag on StemLink — BGC-59 |
| Bass clef (fClef) pitch reconstruction | ✅ Works — G2 base, _fromBassOffset — BGC-59 |
| SyntheticStaffBuilder fallback | ✅ Works — estimates staff from notehead Y distribution |
| Grand staff | ❌ Not supported |
| Chords | ❌ Not supported |
| Ties, slurs, tuplets | ❌ Not supported |

---

## Known Bugs — Not Yet Ticketed

| # | Bug | Where | Priority |
|---|-----|-------|----------|
| B1 | Continue button enabled when no symbols detected | ScanScreen / ScanActions | High |
| B2 | Import button on capture screen bottom nav opens image gallery instead of MusicXML import screen | CaptureScreen | High |
| B3 | No dev JSON import on MusicXML import screen (needed for editor testing) | MusicXML import screen (to be built) | Medium |
| B4 | Score model debug notation preview has near-black background — unreadable in Detection Inspector | di_score_preview.dart | Low |
| B5 | MusicXML Inspector screen uses light theme — inconsistent with app dark theme | music_inspector_screen.dart | Medium |

---

## Ticket Status

### Sprint 1 ✅ Complete
| # | Ticket | Owner |
|---|--------|-------|
| 1 | Setup development environment | Canete |
| 2 | Create OMR model | Canete |
| 3 | Test model | Canete |
| 4 | Build home screen UI | Boleche |
| 5 | Test home screen UI | Galanza |
| 6 | Build music sheet collection screen | Boleche |
| 7 | Test music sheet collection screen | Galanza |
| 8 | Add camera capture and photo import | Boleche |
| 9 | Test capture/import feature | Galanza |
| 10 | IT: Collection + capture/import | Galanza |

### Sprint 2 ✅ Complete
| # | Ticket | Owner |
|---|--------|-------|
| 11 | Build scan screen shell | Boleche |
| 12 | Create preprocessing module | Canete |
| 13 | Create symbol detection module | Canete |
| 14 | IT: Scan screen + preprocessing + detection | Galanza |
| 15 | IT: Scan screen + preprocessing + detection | Galanza |

### Sprint 3 ✅ Complete (regression checklist doc missing)
| # | Ticket | Owner |
|---|--------|-------|
| 16 | Define minimal ScoreModel | Canete |
| 17 | Build MusicXML file import service | Boleche |
| 18 | Build XML parsing layer | Canete |
| 19 | Prepare Sprint 3 MusicXML test assets | Galanza |
| 20 | Build MusicXML validation layer | Canete |
| 21 | Build MusicXML to ScoreModel converter | Canete |
| 22 | Build import test UI | Boleche |
| 23 | Add debug serializer / model inspector | Boleche |
| 24 | Execute import pipeline test cases | Galanza |
| 25 | Create import regression checklist | Galanza |

### Sprint 4 ✅ Complete (regression checklist doc missing)
| # | Ticket | Owner |
|---|--------|-------|
| 26 | Define detection result model | Canete |
| 27 | Define reconstruction rules and assumptions doc | Canete |
| 28 | Build SymbolToScoreMapper skeleton | Canete |
| 29 | Implement basic symbol association rules | Canete |
| 30 | Implement pitch and duration inference | Canete |
| 31 | Build DetectionResult to ScoreModel conversion flow | Canete |
| 32 | Build mapping test UI | Boleche |
| 33 | Add mapping debug serializer | Boleche |
| 34 | Prepare mock detection test assets | Galanza |
| 35 | Execute mapping pipeline test cases | Galanza |
| 36 | Create mapping regression checklist | Galanza |

### Sprint 5 ✅ Complete
| # | Ticket | Owner | Status |
|---|--------|-------|--------|
| 37 | Reconvert YOLO model to 640×640 TFLite | Canete | ✅ Done — int8 model at assets/models/best_int8.tflite |
| 38 | Prepare Sprint 5 editor test assets | Galanza | ⚠️ Partial |
| 39 | Build CustomPainter staff notation viewer | Boleche | ✅ Done |
| 40 | Define editor state model | Canete | ✅ Done |
| 41 | Build undo/redo stack | Canete | ✅ Done |
| 42 | Build editor screen shell | Boleche | ✅ Done |
| 43 | Build symbol selection (notes AND rests) | Canete | ✅ Done |
| 44 | Build move note pitch up/down | Canete | ✅ Done |
| 45 | Build delete symbol (notes AND rests) | Canete | ✅ Done |
| 46 | Build change duration (notes AND rests) | Canete | ✅ Done |
| 47 | Build insert note | Canete | ✅ Done |
| 48 | Build insert rest | Canete | ✅ Done |
| 49 | Build drag-to-reorder symbols within measure | Boleche | ✅ Done |
| 50 | Refine ScoreModel for editor support | Canete | ✅ Done |
| 51 | Improve reconstruction stability for editor | Canete | ✅ Done |
| 52 | IT: Full editor integration test | Canete | ✅ Done |
| 53 | Execute Sprint 5 editor test cases | Galanza | ⚠️ Tests pass, no formal report |
| 54 | Create Sprint 5 editor regression checklist | Galanza | ❌ Not done |

### Sprint 6 ✅ Complete
| # | Ticket | Owner | Duration | Status |
|---|--------|-------|----------|--------|
| 55 | Build symbol palette widget | Boleche | 2H | ✅ Done |
| 56 | Build drag-from-palette-to-staff + hit-test insert | Canete | 4H | ✅ Done |
| 57 | Connect real TFLite detection to reconstruction + staff line pre-pass | Canete | 2H | ✅ Done |
| 58 | IT: Real detection + reconstruction end-to-end | Canete | 1H | ⏳ Not started |
| 59 | Expand reconstruction: key sigs, time sigs, accidentals, beams | Canete | 2H | ✅ Done |
| 60 | Build MusicXML export service + ScoreModel converter | Canete | 2H | ✅ Done |
| 61 | IT: Import → edit → MusicXML export round-trip | Boleche | 2H | ⏳ Not started |
| 61b | Add Save to Device option to MusicXML export | Canete | — | ✅ Done |
| 62 | Build accidental toggle in editor | Canete | 2H | ✅ Done |
| 63 | Build username onboarding + profile photo + display in header | Boleche | 2H | ✅ Done |
| 64 | Prepare Sprint 6 test assets | Galanza | 2H | ⏳ Not started |
| 65 | Execute Sprint 6 test cases | Galanza | 2H | ⏳ Not started |
| 66 | Create Sprint 6 regression checklist | Galanza | 1H | ⏳ Not started |

### Sprint 7 ✅ Complete
| # | Ticket | Owner | Duration | Status |
|---|--------|-------|----------|--------|
| 67 | Build playback module (flutter_midi_pro) | Canete | 3H | ✅ Done |
| 68 | Build playback controls UI | Boleche | 2H | ✅ Done |
| 69 | IT: ScoreModel + playback end-to-end | Canete | 2H | ⏳ Not started |
| 70 | Build engraved PDF renderer | Canete | 4H | ✅ Done |
| 71 | Build PDF export service + share sheet | Boleche | 2H | ✅ Done |
| 72 | IT: ScoreModel + PDF export | Canete | 1H | ⏳ Not started |
| 73 | Define project data model + JSON storage | Canete | 1H | ✅ Done |
| 74 | Build save/load flow + score naming + project list UI | Boleche | 3H | ✅ Done |
| 75 | Prepare Sprint 7 test assets | Galanza | 3H | ⏳ Not started |
| 76 | Execute Sprint 7 test cases | Galanza | 3H | ⏳ Not started |
| 77 | Create Sprint 7 regression checklist | Galanza | 1H | ⏳ Not started |

### Sprint 8 ✅ Complete
| # | Ticket | Owner | Duration | Status |
|---|--------|-------|----------|--------|
| 78 | Improve symbol detection from real-world results | Canete | 3H | ✅ Done |
| 79 | Improve reconstruction from real-world results | Canete | 3H | ✅ Done |
| 80 | Stabilize editor + playback + export post-integration | Canete | 1H | ✅ Done |
| 81 | Add PDF beam rendering | Canete | 2H | ✅ Done |
| 82 | Build local usage stats + profile screen | Boleche | 1H | ✅ Done |
| 83 | IT: Full end-to-end system test on real sheet music | Boleche/Galanza | 1H | ✅ Done |
| 84 | Execute full system regression test cases | Galanza | 3H | ✅ Done |
| 85 | Create final regression checklist | Galanza | 2H | ✅ Done |

### Sprint 9 🔄 In Progress
| # | Ticket | Owner | Duration | Status |
|---|--------|-------|----------|--------|
| 88 | Clean Up Drawer: Remove Digital Writing, Add Instructions & About | Boleche | 2H | ✅ Done (on main) |
| 89 | Editor: Make Playback Controls Static, Utilize Space Below | Boleche | 2H | 🔄 In Progress (pb-bar — approach changed, see delivery notes) |
| 90 | PDF Export: Display Composer for Credits | Canete | 1H | ✅ Done (pb-bar, not merged) |
| 91 | Lock Editor Interactions During Playback | Canete | 2H | ✅ Done (pb-bar, not merged) |
| 92 | Fix XML Import Preview: Black Background Hides Symbols | Boleche | 1H | ✅ Done (pb-bar, not merged) |
| 93 | IT: Sprint 9 Feature Verification & Regression | Galanza | 3H | 🔄 In Progress (pb-bar) |


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

Do not let this file get stale — an outdated CONTEXT.md is worse than no CONTEXT.md.

claude and I can update this from time to time when changes are final

---

## Tickets 67 & 68 Delivery Notes (Sprint 7, branch playback)

Audio playback module + controls UI. All spec criteria satisfied, several above scope:

- **`PlaybackConverter`** — new file `lib/core/services/playback_converter.dart`
  - Pure-Dart, zero platform dependencies — fully unit-testable
  - `noteToMidi(Note)` — MIDI key formula: `(octave + 1) × 12 + stepOffset + alter`; C4=60, A4=69
  - `durationMs(divisions)` — converts MusicXML divisions to ms at 120 BPM (whole=2000, half=1000, quarter=500, eighth=250)
  - `scaledDuration(baseDurationMs, tempo)` — scales base duration to actual BPM
  - `buildEvents(Score)` — flattens Score → `List<PlaybackEvent>` in part→measure→symbol order
  - `PlaybackEvent` model: partIndex, measureIndex, symbolIndex, midiNote (-1=rest), baseDurationMs
- **`PlaybackService`** — new file `lib/core/services/playback_service.dart`
  - Singleton (`PlaybackService.instance`), delegates conversion to `PlaybackConverter`
  - `init()` — loads soundfont asset via `flutter_midi_pro 3.1.6`, graceful error state if SF2 missing
  - `play(Score)` — stops any in-progress playback, builds events, starts loop
  - `pause()` / `resume()` / `stop()` — interrupt-safe via `Completer<bool>` + `Timer`
  - `setTempo(bpm)` — clamps to 20–300, takes effect at next note boundary (real-time)
  - `Stream<PlaybackState>` — emits stopped/playing/paused/error on every transition
  - `Stream<PlaybackPosition>` — emits (partIndex, measureIndex, symbolIndex) per note; `PlaybackPosition.none` on stop
  - Stops automatically when last symbol is reached
- **`PlaybackControlsBar`** — new file `lib/features/editor/presentation/widgets/playback_controls_bar.dart`
  - Play/pause toggle (icon changes with state), stop button, tempo slider 40–200 BPM with live BPM label
  - All controls disabled + greyed when score has no symbols
  - Error indicator (⚠ tooltip) shown when soundfont missing
  - Pinned at the bottom of `EditorShellScreen` below the inspector panel (always visible)
- **`ScoreNotationPainter`** — added `playbackPartIndex/MeasureIndex/SymbolIndex` params
  - `_drawPlaybackHighlight()` — outer glow ring (radius 20, 18% opacity) + filled inner circle (radius 13, 45% opacity) + accent border (1.5 px) — visually distinct from editor selection highlight
  - Drawn before notehead so symbol is still legible on top
- **`ScoreNotationViewer`** — same three playback params forwarded to painter; `shouldRepaint` updated
- **`EditorShellScreen`** — `_initPlayback()` on open, `_positionSub` stream subscription, `stop()` on dispose
- **Soundfont required** — `assets/soundfonts/piano.sf2` (any standard GM SF2). README.txt in that directory. App shows error state + tooltip if missing.
- **flutter_midi_pro 3.1.6 actual API** — `loadSoundfontAsset(assetPath:, bank:, program:)`, `selectInstrument(sfId:, channel:, bank:, program:)`, `playNote(sfId:, channel:, key:, velocity:)`, `stopNote(sfId:, channel:, key:)`, `unloadSoundfont(sfId)`
- **Tests** — `test/core/services/playback_converter_test.dart` — 37 tests across 4 groups: noteToMidi (12), durationMs (7), scaledDuration (4), buildEvents (12), PlaybackPosition (2). All pass.
- **Total suite** — 278 tests, all pass.

---

## BGC-70 & BGC-71 Delivery Notes (Sprint 7, branch BGC-70-71)

### BGC-70 — Engraved PDF Renderer

- **`PdfScoreRenderer`** — new file `lib/features/pdf/pdf_score_renderer.dart`
  - Uses low-level `PdfDocument` / `PdfGraphics` API from the `pdf: ^3.11.1` package (no widget layer)
  - Returns `Future<Uint8List>` — raw PDF bytes, no I/O, easy to test
  - A4 portrait, 20 mm margins, `PdfFont.courier` for text
  - **Pagination**: measures-per-system computed from page width minus margins and prefix; systems-per-page computed from page height; overflows continue on next page
  - **Title block** (first page only): title in 16pt bold top-left, composer in 9pt right-aligned
  - **Staff lines**: 5 lines at 6 pt spacing; staff height = 24 pt
  - **Clef**: treble (`G`) and bass (`F`) drawn with bezier curves in `_drawTrebleClef` / `_drawBassClef`
  - **Key signature**: sharps/flats at correct staff positions using same `StaffPitchMapper.yForPitch` math as CustomPainter viewer; clef-aware treble/bass orders
  - **Time signature**: digit pair drawn at correct staff positions
  - **Noteheads**: filled ellipse (quarter/eighth), open ellipse (whole/half) with white inner ellipse for half
  - **Stems**: up-stem for notes below middle line, down-stem above; length = 3.5 × line spacing
  - **Flags**: cubic bezier on eighth note stems
  - **Ledger lines**: drawn above/below staff when note is outside the 5-line range
  - **Rests**: filled rect (whole), filled rect (half), zigzag path (quarter)
  - **Barlines**: at end of each measure and at system open/close
  - **Measure numbers**: 6pt above first beat of each measure

### BGC-71 — PDF Export Service + Share Sheet

- **`PdfExportService`** — new file `lib/features/pdf/pdf_export_service.dart`
  - ~~`exportAndShare(Score)`~~ → replaced by `exportToDevice(Score) → Future<String?>` (see post-BGC-70-71 refactor below)
  - Opens system OS save dialog via `file_picker`; returns saved path or `null` if user cancels
  - Filename via shared `safeExportFileName(title)` utility
- **Export popup in editor header expanded** (`_EditorHeader` in `editor_shell_screen.dart`)
  - Three menu items: "Export MusicXML…", "Save MusicXML to Device", "Export PDF…"
  - "Export PDF…" item disabled (greyed) when score is empty
  - Tapping "Export PDF…" shows a loading dialog (`CircularProgressIndicator`) while rendering; dialog dismissed in `finally` block whether export succeeds or fails
  - On error, shows a `SnackBar` with the error message

---

## BGC-74 Delivery Notes (Sprint 7, branch BGC-73)

- **Save button wired** — existing `FilledButton.icon(Icons.save_rounded)` in `_EditorHeader` now calls `onSave`; `_EditorShellScreenState._onSave()` drives the save flow
- **First-save name dialog** — `_showNameDialog()` prompts with a text field defaulting to the score title; cancel aborts, empty name aborts; accepts Enter key or button tap
- **Silent re-save** — `_currentProject` (type `Project?`) is tracked in state; if non-null, `copyWithUpdated(score:)` is called and saved with no dialog
- **Save confirmation snackbar** — "Saved as [name]" appears for 2 seconds after every successful save; `hasUnsavedChanges` cleared immediately after save
- **`EditorShellArgs.existingProject`** — optional `Project?` field added; set when opening from project list so the editor knows it already has a project id
- **Unsaved changes guard** — `PopScope(canPop: !hasUnsavedChanges)` wraps the Scaffold; system back and header back button both route through `_handlePopAttempt()` which shows a "Leave without saving?" dialog
- **`ProjectListScreen`** — ~~`lib/features/projects/presentation/project_list_screen.dart`~~ **deleted** (see post-BGC-70-71 refactor below — merged into `CollectionScreen`)
- **Navigation entry points** — originally "Saved Projects" folder icon + drawer item; after merge, CollectionScreen itself is the project list
- All 224 existing tests pass; no new test file (UI-only screen, integration tested manually per DoD)

---

## BGC-73 Delivery Notes (Sprint 7, branch BGC-73)

- **ScoreModel serialization** — `toJson()` added as abstract method on `ScoreSymbol`; all concrete types implement it with a `symbolType` discriminator field (`'note'`, `'rest'`, `'clef'`, `'keySignature'`, `'timeSignature'`). `fromJson()` factory added to each. `Measure._symbolFromJson()` does the dispatch. `Measure`, `Part`, and `Score` chain through children.
- **`Project` model** — `lib/core/models/project.dart`
  - Fields: `id` (millisecondsSinceEpoch string), `name`, `createdAt`, `updatedAt`, `scoreJson` (Score serialized as JSON string)
  - `Project.create(name, score)` — factory that sets id + both timestamps to now
  - `decodeScore()` — deserializes `scoreJson` back to a `Score`
  - `copyWithUpdated({name, score})` — returns a copy with refreshed `updatedAt`; `createdAt` and `id` are preserved
  - Full `toJson()` / `fromJson()` round-trip
- **`ProjectStorageService`** — `lib/core/services/project_storage_service.dart`
  - `saveProject(Project)` — writes `{docsDir}/projects/{id}.json`, upserts master index
  - `loadProject(String id)` — reads and deserializes; returns null if file missing
  - `loadAllProjects()` — reads index, loads all files, sorts by `updatedAt` descending
  - `deleteProject(String id)` — deletes file + removes from index; no-ops silently if missing
  - Master index in `SharedPreferences` key `project_index` as a JSON list of `{id, name}` maps
  - Accepts injectable `projectsDirOverride` constructor param for testing (no platform mocking needed)
- **Tests** — `test/core/models/project_serialization_test.dart` — 34 tests: per-type round-trips for all symbol classes, Measure/Part/Score deep round-trip, unknown symbolType throws FormatException, Project model lifecycle, full storage service behaviour; all 224 tests pass

---

## MusicXML Save to Device — Delivery Notes (Sprint 6, branch claude/musicxml-export-feature-zwSqL)

> **Note:** The platform-specific Downloads/Documents approach was replaced in the post-BGC-70-71 refactor (see below). Current implementation uses `file_picker` system save dialog.

- ~~`MusicXmlExportService.exportToDevice(Score) → Future<File>`~~ → now `Future<String?>` via `file_picker` (returns path or `null` if cancelled)
- ~~`exportAndShare`~~ removed — share_plus flow dropped in favour of unified file picker save
- **Editor header export popup** — three items: "Export MusicXML…" (share sheet, kept), "Save MusicXML to Device" (file picker), "Export PDF…" (file picker)
- **SnackBar feedback** — on success shows saved path; null return (user cancelled) shows no feedback; on failure shows error
- All tests pass

---

## Post-BGC-70-71 Delivery Notes (SP7-test branch, after BGC-70-71 merge)

Six commits landed after the BGC-70-71 merge. No new Jira tickets — these are refinements and clean-ups.

### CollectionScreen ← ProjectListScreen merge (64441eb)
- `lib/features/projects/presentation/project_list_screen.dart` **deleted**
- `CollectionScreen` now owns the full project list UI: loads `List<Project>` via `ProjectStorageService`, shows project tiles, tap → editor, long-press → delete confirm
- Drawer entry and `/projects` route removed from `main.dart`; `CollectionScreen` is the single entry point for the collection

### MusicXML save via system file picker (7643a94)
- `MusicXmlExportService.exportAndShare` removed; `exportToDevice(Score) → Future<String?>` rewritten to call `FilePicker.platform.saveFile(...)` instead of writing to Downloads/Documents
- `path_provider` and `share_plus` removed from this service; `file_picker` used instead
- Caller receives saved path or `null` (user cancelled)

### Drag-to-trash delete gesture (597bcd1)
- Delete button removed from the editor inspector panel
- `ScoreNotationViewer` — symbols can now be dragged; dropping onto the trash zone in `EditorShellScreen` triggers `deleteSelectedSymbol()`
- Trash zone only appears while a drag is in progress; icon-only (no label)

### Cross-measure/part drag reorder + icon-only trash (fa79866)
- `EditorActions.moveSymbolToDest(fromPart, fromMeasure, fromSymbol, toPart, toMeasure, toSymbol)` added to `editor_actions.dart`
  - Same-measure path: delegates to existing `reorderSymbol` (no behaviour change)
  - Cross-measure path: deletes from source measure, inserts at destination; selection follows the moved symbol
  - Cross-part supported — allows moving between treble/bass staves
- `ScoreNotationViewer` drag callbacks updated to use `onDragCompleted` API
- Trash zone updated to icon-only (no text label)

### Unified export filename utility (0e2382f)
- `lib/core/utils/export_file_name.dart` — `safeExportFileName(title)` replaces the duplicate `_safeFileName` private helpers in both `MusicXmlExportService` and `PdfExportService`
- `PdfExportService.exportAndShare` → renamed `exportToDevice(Score) → Future<String?>`, opens `FilePicker.platform.saveFile(...)` — same pattern as XML
- `EditorShellScreen` export menu simplified: both XML and PDF paths call `exportToDevice`; show path snackbar on success, no-op on null (cancelled)
- **Tests added** — `test/core/utils/export_file_name_test.dart` (10 tests); `moveSymbolToDest` covered in `editor_actions_test.dart` (7 new cases: same-measure, same-position no-op, cross-measure, destination clamp, cross-part, invalid-fromPart guard, invalid-toPart guard). Suite total: 278.

---

## BGC-62 Delivery Notes (Sprint 6, branch BGC-57 / 57-copy)

- **`setSelectedNoteAccidental(int? alter)`** added to `EditorActions` extension in `editor_actions.dart`
  - No-ops if not a Note, or if value is already the same (idempotent)
  - Preserves all other note fields; undo tracked automatically via `_replaceSelectedSymbol`
- **Accidental rendering in `ScoreNotationPainter._drawNote()`**
  - Draws `♯ ♭ ♮ 𝄪 𝄫` immediately left of the notehead using `TextPainter`
  - Positioned at `x - glyphWidth - 3px`, vertically centered on note Y
  - Applies to all notes with `alter != null` including double accidentals from reconstruction
- **ACCIDENTAL group added to `_InspectorPanel`** (between PITCH and DURATION)
  - 4 tiles: `— None · ♯ Sharp · ♭ Flat · ♮ Natural`
  - New `_AccTile` widget: same shape as `_DurTile` with `isActive` state
  - Active tile highlighted with accent color `Color(0xFFD4A96A)` background + border
  - Tiles disabled (greyed) when a Rest is selected or nothing is selected
  - Active tile auto-updates when selection changes to a different note
  - Tapping the active tile again is a no-op (direct select, not cycle toggle — better UX than spec)

---

## BGC-59 Delivery Notes (Sprint 6, branch BGC-59 merged into BGC-57)

Full expanded reconstruction pipeline. All spec criteria satisfied, several above scope:

- **Key signature** — `SignatureInferrer.inferKeySignature` counts leading accidentals → `KeySignature(fifths: ±count)`
- **Time signature** — digit pairs split by staff midpoint; `timeSigCommon`→4/4, `timeSigCutCommon`→2/2
- **Note-level accidentals** — `SemanticInferrer._matchAccidentalsToNoteheads` proximity-matches body accidentals to nearest notehead to the right; `SymbolClassifier.alterFor()` maps type → MusicXML alter value
- **Beamed eighth notes** — `StemAssociator._hasNearbyBeam` sets `StemLink.hasBeam`; `SemanticInferrer._buildNote` treats `hasBeam || hasFlag` → `'eighth'`
- **Bass clef pitch** — `PitchCalculator._fromBassOffset` with G2 as bottom-line base
- **Expanded rest types** — `rest8th` → `'eighth'`, `rest16th` → `'sixteenth'`
- **Double accidentals** — `isAnyAccidental` + `alterFor` handle `accidentalDoubleSharp`/`accidentalDoubleFlat` (above spec)
- **`expanded_reconstruction_test.dart`** — 13 new tests across 4 groups: accidentals (5), beams (3), rests (2), bass clef (3)
- **Sprint 4 test fixes** (3 tests) — updated for BGC-57 multi-part behavior: part name `'Detected Part'` → `'Treble'`; multi-staff test updated from `parts.single` to asserting two parts with correct content

---

## Multi-Staff Editor + Measure Management (branch `assume`, post-BGC-57)

Session work committed on `assume` branch (not yet a formal ticket):

- **`Score.insertMeasureAfterInAllParts(int measureIndex)`** — inserts an empty measure after the given index in every part simultaneously, then renumbers all measures 1-indexed. Keeps multi-part staves in sync.
- **`Score.deleteMeasureFromAllParts(int measureIndex)`** — removes a measure from every part simultaneously, renumbers.
- **`EditorActions.addMeasureAfterSelected()`** — inserts after the selected measure, selects the new measure.
- **`EditorActions.deleteSelectedMeasureIfEmpty()`** — guards: measure count > 1 AND `symbols.isEmpty`. No-ops otherwise.
- **Inspector panel** — MEASURE group gains two tiles: `Add` (always enabled when measure context exists) and `Del` (enabled only when measure is empty and count > 1, rendered red/danger).
- **Multi-staff drag-drop fix** — `_resolveInsertTarget` in `score_notation_viewer.dart` was using a single-part Y formula (`padding.top + rowIndex * rowHeight`). Rewrote to iterate `systemRows × parts` with the correct multi-part formula: `padding.top + systemIndex * (partCount * rowHeight) + partIdx * rowHeight + 28`. Drag-drop and insert-mode tap now work on all staves.
- **`NotationInsertTarget.partIndex`** — added field (default 0); wired through all 3 call sites in `score_notation_viewer.dart` and both handlers in `editor_shell_screen.dart`.
- **Multi-staff operation fixes** — `reorderSymbolWithinMeasure` and `onPrevMeasure`/`onNextMeasure` callbacks were hardcoded to part 0; updated to use `selectedPartIndex`.
- **Beam fallback** — see noteheadBlack heuristic section below (case 3 added this session).

---

## noteheadBlack Stem Assumption Heuristic (post-BGC-59, branch BGC-57)

Implemented in `SemanticInferrer._buildNote()`:

- **Problem:** YOLO frequently misses stems (thin vertical lines). A `noteheadBlack` with no detected stem was silently dropped — the note disappeared entirely from the reconstructed score.
- **Fix:** Added a terminal fallback case `'noteheadBlack' => 'quarter'` in the `_buildNote` switch. When no stem is detected alongside a black notehead, the note is assumed to be a quarter note rather than discarded.
- **Rationale:** A slightly-wrong duration (quarter instead of eighth/quarter) is far less damaging than a missing note. Pitch reconstruction is unaffected.
- **Note still dropped if:** pitch calculation fails (e.g., no clef in the measure) — that guard is independent of this heuristic.
- **Switch order (in priority):**
  1. `noteheadBlack` with stem + flag/beam → eighth
  2. `noteheadBlack` with stem (no flag/beam) → quarter
  3. `noteheadBlack` with beam but no stem → eighth (beams are thicker, easier for model to detect than thin stems)
  4. `noteheadBlack` (no stem, no beam) → quarter ← fallback
- **Test impact:** Two tests in `detection_to_score_mapper_service_test.dart` updated:
  - "ambiguous noteheads" — now asserts 1 quarter note produced (clef present, pitch succeeds); previously expected empty symbols + "Could not infer" warning
  - "partial mapped score" — now asserts empty symbols with "Could not calculate pitch" warning (clef absent → pitch fails after switch succeeds); previously expected empty symbols + "Could not infer" warning

---

## Barline Detection — WIP (branch `feature/barline-detection`, parked)

Work-in-progress on branch `feature/barline-detection` (branched from `assume`). Not yet production-ready. **Do not merge to `assume` or `main` until tuned.**

- **`VerticalProjectionBarlineDetector`** — per-column analysis inside each detected staff.
  - Probes each of the 5 known `lineYs` positions (±`lineTolerancePx=2` px) for a dark pixel.
  - Column is a barline candidate if it hits ≥ `minLineHits=4` of the 5 staff lines.
  - Barlines cross all 5 lines; stems only touch 1–2 → strong discriminator.
  - Clusters consecutive candidate columns into bands; filters by max band width (8px) and edge margin (4%) to remove boundary lines.
- **`DetectionResult`** already carries `barlines: List<DetectedBarline>` (committed to main pipeline).
- **`DetectionOverlay`** renders barlines as 2px amber vertical lines spanning staff height when present.
- **Status:** Algorithm not yet tested on real data. Tuning levers:
  - Too many → raise `minLineHits` to 5
  - Too few → lower `minLineHits` to 3, or raise `lineTolerancePx` to 3

---

## BGC-57 Delivery Notes (Sprint 6, branch BGC-57)

Real TFLite detection connected to reconstruction pipeline end-to-end. Major changes:

- **`TfliteSymbolDetector` — single inference path**: full image always stretched to 640×640, no tiling, no letterboxing. `_parseOutput` uses normalized (0–1) XYXY coords, scales back via `origW/640 × origH/640`.
- **Detection overlay fix (`DetectionOverlay`)**: `LayoutBuilder` computes `scaleX = displayW / imageW`, `scaleY = displayH / imageH`; all `Positioned` coordinates multiplied by scale factors. Fixes misalignment caused by `InteractiveViewer(constrained: true)` squeezing child to viewport size while overlay used raw pixel coords.
- **`DetectionOverlay` params**: now requires `imageWidth` and `imageHeight`; `_StaffOverlay` receives `scaleX`/`scaleY`.
- **`_mergeStaves`**: model combStaff detections preferred; HorizontalProjectionStaffDetector staves used as supplement only when model missed a staff.
- **`SyntheticStaffBuilder`**: estimates staff geometry from notehead Y distribution when neither source produces staves.
- **Multi-part pipeline in `DetectionToScoreMapperService`**: iterates all staves, produces one `Part` per staff (`'Treble'`, `'Bass'`, `'Staff N'`). `ScoreBuilder.buildPart()` and `buildFromParts()` added.
- **`MappingResult.staffSource`**: `'synthetic'` when SyntheticStaffBuilder was used, null otherwise.
- **`ScoreNotationViewer`** updated to render multi-part scores (one staff row per part).
- **`EditorShellScreen`** updated for multi-part `Score` structure.

---

## BGC-60 Delivery Notes (Sprint 6, branch BGC-55-56)

- **`MusicXmlExportService`** — new file `lib/features/musicXML/musicxml_export_service.dart`
  - `toMusicXml(Score)` — pure function, returns valid MusicXML 3.1 string (no I/O, fully unit-testable)
  - `exportAndShare(Score)` — writes `.musicxml` to temp dir, opens system share sheet via `share_plus`
  - Builds: `<work>`, `<identification>` (with `<encoding>`), `<part-list>`, `<part>` → `<measure>` → `<attributes>` (on first measure or when clef/key/time present) → `<note>` / `<rest>`
  - `divisions` hardcoded to `2` (matching our quarter=2 convention); `alter` omitted when null or 0
  - `voice` and `staff` elements emitted only when present on the model
  - XML DOCTYPE header prepended manually (xml package doesn't support DOCTYPE nodes)
  - `_safeFileName` replaces non-word characters with underscores for safe file naming
- **Export button wired into editor** — `_EditorHeader` originally had a single `ios_share_rounded` icon, later replaced by a `PopupMenuButton` with "Share…" and "Save to Device" (see Save to Device delivery notes)
- **`share_plus: ^12.0.2` added** to pubspec (resolved by `flutter pub add` due to web package conflict with file_picker)
- **Landing screen test fix** — `Pressing Get Started navigates to CollectionScreen` required `SharedPreferences.setMockInitialValues({'onboarding_complete': true})` because `UserProfileService.isOnboardingComplete()` reads SharedPreferences asynchronously
- **`!mounted` / `this.context` pattern** — `landing_screen.dart` now correctly guards async gap with `State.mounted` (`if (!mounted) return`) then uses `this.context` (State's own context), not `context.mounted` on the parameter

---

## Sprint 8 Delivery Notes

### BGC-78 & BGC-79 — Improved Detection + Reconstruction (branch bgc-78-79)

- YOLO confidence threshold tuned; reconstruction pipeline hardened against real-world edge cases
- `feat(stats): track edits per score instead of globally` — analytics now per-project

### BGC-80 — Stabilize Editor + Playback + Export

- **Auto-scroll during playback** — `ScoreNotationViewer` scrolls to keep the highlighted note visible
- **Soundfont double-load fix** — `PlaybackService` guards against being initialized twice; `dispose()` now correctly unloads the soundfont and cancels the timer to prevent audio leaks
- **P0/P1/P2 bug fixes from sprint 8 audit** — editor shows project name in header instead of score title; `.musicxml` extension dropped in favour of `.xml` only; MusicXML importer tests updated; profile screen setState issues resolved

### BGC-81 — PDF Beam Rendering (branch 81)

- `PdfScoreRenderer` now draws beams connecting consecutive eighth-note stems in the same measure
- Beam is a filled rect spanning from the tip of the first stem to the tip of the last stem in a beamed group

### BGC-82 — Usage Stats + Profile Screen (branch bgc-82)

- **`UsageStatsService`** — increments scan/edit/export/playback counters in `SharedPreferences`; edit counter is per-score, not global
- **`ProfileStatsScreen`** — displays username, profile photo, and local usage counters; accessible from the drawer

---

## Sprint 9 Delivery Notes (in progress, branch pb-bar)

### BGC-88 — Clean Up Drawer: Instructions + About Screens

- `InstructionsScreen` and `AboutScreen` added; accessible from the app drawer
- "Digital Writing" drawer item removed
- Widget tests added for both screens

### BGC-89 — Editor: Make Playback Controls Static, Utilize Space Below

Scope evolved across multiple iterations on branch `pb-bar`:

**Attempt 1 — two-row playback bar** (`8443544`, reverted `8d20526`)
- Expanded `PlaybackControlsBar` to two rows (transport + tempo); `SafeArea` aware
- Reverted after UX review — controls felt cramped; bottom space still underused in portrait

**Approach shift — portrait inspector moved to bottom bar**
- Rather than expanding the playback bar, the portrait inspector panel (previously a right-side floating vertical toolbar) was redesigned as a `_BottomInspectorBar` sitting directly above `PlaybackControlsBar`
- This fully utilizes the bottom zone and keeps `PlaybackControlsBar` static and uncluttered
- Canvas gets full width back; playback bar never moves

**Changes shipped on pb-bar (not yet merged to main):**
- `_BottomInspectorBar` — 56 px horizontal bar (`_kInspectorBarHeight = 56.0`) with four tabs: PITCH, ACCIDENTAL, DURATION, MEASURE
- Tapping a tab opens a popup that floats upward (`bottom: _kInspectorBarHeight + 8`); tapping canvas or another tab dismisses it
- `_wrapAction` — thin passthrough (`VoidCallback? _wrapAction(action) => action`); popup stays open after action so user can repeat (e.g. pitch Up/Down multiple times)
- INSERT group removed from inspector (Note/Rest insert is already covered by drag-from-palette)
- Drag-to-delete regression fixed: `_NotationArea` gains `showTrashZone` param; in portrait the trash zone overlays the inspector bar at `bottom: 0, height: _kInspectorBarHeight` during a drag

### BGC-90 — PDF Export: Display Composer for Credits

Nearly fully pre-built — only one bug found and fixed:

- `_showMetadataSheet` in `EditorShellScreen` already existed with Title + Composer fields, pre-filled from `score.title` / `score.composer`, saves via `_updateState`
- `PdfScoreRenderer._drawTitleBlock` already renders `score.composer` at top-right of first page when non-empty
- `MusicXmlExportService` already emits `<creator type="composer">` when set
- `Score.toJson` / `Score.fromJson` already serialised `composer`
- **Bug fixed:** `Score.fromJson` was casting `json['composer'] as String` (non-nullable) — crashes when loading projects saved before the `composer` field existed. Fixed to `(json['composer'] as String?) ?? ''`
- Regression test added: `fromJson defaults composer to empty string when field is absent`

### BGC-91 — Lock Editor Interactions During Playback

Implemented in `lib/features/editor/presentation/editor_shell_screen.dart`:

- **Playback status tracking** — `_EditorShellScreenState` adds `PlaybackStatus _playbackStatus` and `StreamSubscription<PlaybackState>? _stateSub`; subscribes to `PlaybackService.stateStream` in `_initPlayback()`, cancels in `dispose()`
- **`isPlaybackActive` flag** — derived as `_playbackStatus == PlaybackStatus.playing` in `build()`; threaded into `_NotationArea`, `_InspectorPanel`, and `_EditorHeader`
- **Locked interactions when playing:**
  - **Symbol tap / insert tap / drag-to-reorder** — `onSymbolTap`, `onInsertTap`, `onDragStarted` nulled in `ScoreNotationViewer` bindings
  - **External palette drop** — `canAcceptExternalDrop` returns false; `onExternalDrop` nulled
  - **Symbol palette** — wrapped with `IgnorePointer(ignoring: isPlaybackActive)`; `selectedType` forced to null
  - **Insert-mode toggle** — `_FloatingControls.onToggleInsertMode` replaced with a no-op; `insertMode` forced to false visually
  - **Inspector actions** — `_wrapAction()` in `_InspectorPanelState` returns null when `isPlaybackActive`, which disables all pitch/accidental/duration/measure tiles automatically
  - **Portrait inspector popup** — auto-closed in `_InspectorPanelState.didUpdateWidget` when playback starts; `_BottomInspectorBar` gains `disabled` param — tab taps suppressed and icons greyed (30% opacity)
  - **Undo / Redo** — `canUndo && !isPlaybackActive` / `canRedo && !isPlaybackActive` in header; buttons grey out during playback
- **Pan/zoom unaffected** — `InteractiveViewer` is untouched; user can still scroll and zoom to follow the playback highlight
- **Lock scope** — `playing` state only; `paused` leaves interactions enabled so the user can edit between playback sessions
- **No new tests** — all changes are UI-layer gating; 278 existing tests pass

### BGC-93 — IT: Sprint 9 Feature Verification & Regression (partial)

Automated test coverage added for BGC-91 (playback lock). Manual device testing of all Sprint 9 features still required from Galanza.

**BGC-91 test group** — 8 new tests in `test/features/editor/presentation/editor_shell_screen_test.dart`:
- `landscape: action tiles have callbacks before playback` — baseline: Up/Down tiles enabled before playing
- `landscape: action tiles are nulled while playing` — Up/Down/Add all null when `PlaybackStatus.playing`
- `landscape: interactions restored when playback stops` — Up tile re-enables after `stopped`
- `landscape: undo button disabled while playing` — undo `IconButton.onPressed` is null while playing
- `landscape: ScoreNotationViewer callbacks nulled while playing` — `onSymbolTap` and `onDragStarted` null while playing
- `portrait: tab taps suppressed while playing` — tapping PIT tab does not open popup while playing
- `portrait: open popup hidden when playback starts` — open popup is hidden when playing starts
- `portrait: tabs re-enable after playback stops` — PIT tab opens popup again after stop

**Supporting changes:**
- `PlaybackService.emitStateForTesting(PlaybackState)` — `@visibleForTesting` hook added to allow simulating playback state in tests (`lib/core/services/playback_service.dart`)
- `_initPlayback()` reordered — `_positionSub`/`_stateSub` subscribed BEFORE `await _playback.init()` so state changes are received even if soundfont load is slow or never completes in tests
- `_InspectorPanelState.didUpdateWidget` — uses `addPostFrameCallback` + `setState` to reset `_activeGroupIndex = null` when playback becomes active (avoids popup reappearing when playback stops)
- `_InspectorPanelState.build` — popup condition guarded with `&& !widget.isPlaybackActive` as a defence-in-depth visual suppression during the frame before the setState fires

**Full suite: 286 tests, all pass.**

**Manual regression still needed (Galanza):**
- BGC-88: Instructions and About screens open from drawer correctly, Digital Writing removed
- BGC-89: Portrait bottom inspector bar tabs open/close popups; playback controls visible and static
- BGC-90: PDF export includes composer credit on first page
- BGC-91: On-device — editor is non-interactive during playback, re-enables after stop/pause
- BGC-92: MusicXML import preview shows symbols on light background
- Full scan → edit → export end-to-end regression

### BGC-92 — Fix XML Import Preview Background

- `fix(import): use light background on score preview container` (`2a2e557`)
- Import screen preview container now uses `Color(0xFFF9FAFB)` background instead of `AppColors.surface` — symbols are legible before the user taps Continue
- Done on pb-bar, not yet merged to main

- **Before:** right-side floating vertical toolbar (iBis Paint X style), 58 px wide, overlapped the canvas
- **After:** `_BottomInspectorBar` — 56 px horizontal bar (`_kInspectorBarHeight = 56.0`) pinned above `PlaybackControlsBar`
  - Four tab buttons: PITCH, ACCIDENTAL, DURATION, MEASURE (each `Expanded`)
  - Active tab highlighted with accent top border + tinted background
  - Tapping a tab opens a `_ToolGroupPopup` that floats upward (`bottom: _kInspectorBarHeight + 8`)
  - Popup stays open after action — close by re-tapping the same tab or tapping the canvas barrier
- Canvas in portrait mode gets `Padding(bottom: _kInspectorBarHeight)` so it doesn't scroll under the bar
- Landscape is unchanged — side panel layout retained

**Remove INSERT inspector group**

- INSERT group (Note + Rest buttons) removed from `_InspectorPanel._buildGroups()`
- `onInsertNote` / `onInsertRest` params dropped from `_InspectorPanel` constructor
- Insert is still available via drag-from-palette; `EditorActions.insertNoteAfterSelection()` / `insertRestAfterSelection()` kept for future use
- `_groupIcons` reduced from 5 to 4 entries

**Fix drag-to-delete regression**

- **Root cause:** adding `Padding(bottom: _kInspectorBarHeight)` to the notation area shrunk the canvas by 56 px, pushing the internal `_TrashZone` up off the bottom edge — users dragging to the very bottom of the screen missed it
- **Fix:** `_NotationArea` gains a `showTrashZone` bool (default `true`); set to `false` in portrait so the internal zone is suppressed
- A `_TrashZone` is overlaid in the portrait Stack at `Positioned(left: 0, right: 0, bottom: 0, height: _kInspectorBarHeight)` — appears on top of the inspector bar only while a drag is in progress (`if (_isDraggingNote)`)
- Landscape is unaffected (`showTrashZone: isLandscape`)

### Auto-close popup on every inspector action

- `_wrapAction(VoidCallback? action)` is a thin passthrough — popup stays open after any button tap so the user can repeat actions (e.g. pitch Up/Down multiple times). Close by re-tapping the active tab or tapping the canvas barrier.

---

## BGC-55-56 Delivery Notes (Sprint 6, branch BGC-55-56)

Shipped beyond the ticket spec:

- **Editor UI full redesign** — new header, floating controls, landscape side panel, portrait bottom panel, `_SelectionCard`, `_ActionTile`, animated mode pill
- **Insert mode** — tap palette item to enter insert mode, tap canvas to place symbol at that exact position; tap same item again exits insert mode
- **Bass clef rendering** — `ScoreNotationPainter` now renders F-clef with dots; `StaffPitchMapper` is clef-aware (G/F); key signature accidental positions also clef-aware
- **Eighth note duration fix** — `eighthDuration` was `DurationSpec('eighth', 1)` matching quarter — corrected to distinct value; all DurationSpec constants now: whole=8, half=4, quarter=2, eighth=1
- **`insertSymbolAtMeasureIndex`** — new `EditorActions` method for precise index-targeted insert (used by canvas drop and insert mode)
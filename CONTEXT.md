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
   insert note/rest, drag-to-reorder, undo/redo (50 levels)
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

  features/
    landing/                         LandingScreen — entry point
    collection/                      CollectionScreen — saved score grid
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
        widgets/symbol_palette.dart  Draggable note/rest palette (Sprint 6)
    musicXML/                        Import pipeline
      musicxml_importer.dart         File pick + read + decompress
      musicxml_parser_service.dart   XML parse + validate
      musicxml_validator_service.dart Structural validation
      musicxml_score_converter.dart  XML → ScoreModel
    musicxml_inspector/              Dev tool — MusicXML inspector screen
    detection_inspector/             Dev tool — Detection pipeline inspector

assets/
  models/best_int8.tflite            YOLO model — 640×640 int8 quantized (replaces omr_model.tflite)
  fonts/                             MaturaMTScriptCapitals
  images/                            notevision.png logo

test/
  musicxml_testfiles/                7 XML test files (valid, invalid, edge cases)
  features/                          Unit + widget tests per feature
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
- **Insert default:** C4 quarter note / quarter rest, appended to end of selected measure, auto-selected after insert
- **Drag insert:** LongPressDraggable from palette → DragTarget on staff. Drop Y → pitch via PitchCalculator. Drop X → insert index.
- **PDF export:** `pdf` package with programmatic Canvas drawing — replicates CustomPainter logic
- **Audio playback:** `flutter_midi_pro` — synthesizes from Note step+octave+duration directly
- **Save/load:** JSON files in app documents directory via path_provider. Project index in shared_preferences.
- **MusicXML export:** `xml` package, valid MusicXML 3.1, shared via share_plus
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
insertNoteAfterSelection()          // Appends C4 quarter, auto-selects
insertRestAfterSelection()          // Appends quarter rest, auto-selects
reorderSymbolWithinMeasure()        // Cannot cross measure boundary
moveSelectedSymbolToMeasureOffset() // Move symbol to adjacent measure
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

### Sprint 5 🔄 In Progress
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

### Sprint 6 🔄 In Progress
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

### Sprint 7 🔄 In Progress
| # | Ticket | Owner | Duration | Status |
|---|--------|-------|----------|--------|
| 67 | Build playback module (flutter_midi_pro) | Canete | 3H | ⏳ Not started |
| 68 | Build playback controls UI | Boleche | 2H | ⏳ Not started |
| 69 | IT: ScoreModel + playback end-to-end | Canete | 2H | ⏳ Not started |
| 70 | Build engraved PDF renderer | Canete | 4H | ✅ Done |
| 71 | Build PDF export service + share sheet | Boleche | 2H | ✅ Done |
| 72 | IT: ScoreModel + PDF export | Canete | 1H | ⏳ Not started |
| 73 | Define project data model + JSON storage | Canete | 1H | ✅ Done |
| 74 | Build save/load flow + score naming + project list UI | Boleche | 3H | ✅ Done |
| 75 | Prepare Sprint 7 test assets | Galanza | 3H | ⏳ Not started |
| 76 | Execute Sprint 7 test cases | Galanza | 3H | ⏳ Not started |
| 77 | Create Sprint 7 regression checklist | Galanza | 1H | ⏳ Not started |

### Sprint 8 ⏳ Not Started
| # | Ticket | Owner | Duration |
|---|--------|-------|----------|
| 78 | Improve symbol detection from real-world results | Canete | 3H |
| 79 | Improve reconstruction from real-world results | Canete | 3H |
| 80 | Stabilize editor + playback + export post-integration | Canete | 1H |
| 81 | Add PDF beam rendering | Canete | 2H |
| 82 | Build local usage stats + profile screen | Boleche | 1H |
| 83 | IT: Full end-to-end system test on real sheet music | Boleche/Galanza | 1H |
| 84 | Execute full system regression test cases | Galanza | 3H |
| 85 | Create final regression checklist | Galanza | 2H |

---

## What Is Not In Jira Yet

These were discussed and agreed but not yet added as tickets:

- Fix B1: Continue button enabled with no detections
- Fix B2: Import button → dedicated MusicXML import screen (user-facing, not just dev tool)
- Fix B3: Import JSON with DEV label on MusicXML import screen
- Fix B4: Score model debug preview dark background
- Fix B5: MusicXML inspector dark theme
- Staff line detection + removal pre-pass (between preprocessing and detection)
- Expand ticket 63 scope to include profile photo (already reflected above)
- Expand ticket 82 scope to be profile + stats combined screen

---

## What the App Cannot Do (Current Limits)

These are current limitations, not hard ceilings — going beyond them is fine if it makes the app better.

- Bass clef rendering ✅ done in editor; alto clef, tenor clef still unsupported
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
- Multi-page score layout (Sprint 7 PDF wraps staves but single score only)
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

## BGC-70 & BGC-71 Delivery Notes (Sprint 7, branch BGC-73)

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
  - `exportAndShare(Score)` — calls renderer, writes bytes to temp file in app cache, opens system share sheet via `share_plus`, deletes temp file in `finally` block
  - File named `<safe_title>.pdf` (spaces/special chars → underscores)
- **Export popup in editor header expanded** (`_EditorHeader` in `editor_shell_screen.dart`)
  - Three menu items: "Export MusicXML…", "Save MusicXML to Device", "Export PDF…"
  - "Export PDF…" item disabled (greyed) when score is empty
  - Tapping "Export PDF…" shows a loading dialog (`CircularProgressIndicator`) while rendering; dialog dismissed in `finally` block whether export succeeds or fails
  - On error, shows a `SnackBar` with the error message

---

## MusicXML Save to Device — Delivery Notes (Sprint 6, branch claude/musicxml-export-feature-zwSqL)

- **`MusicXmlExportService.exportToDevice(Score) → Future<File>`** — new method alongside `exportAndShare`
  - Android: writes to Downloads folder via `getDownloadsDirectory()`, falls back to `getApplicationDocumentsDirectory()` if null
  - iOS: writes to app Documents directory, accessible via Files app under "On My iPhone"
  - Returns the saved `File` so callers can display the path
- **Editor header export button replaced with `PopupMenuButton`**
  - Two items: "Share…" (existing share sheet) and "Save to Device" (new direct save)
  - New `_ExportOption` enum and `_ExportMenuItem` widget added to `editor_shell_screen.dart`
- **SnackBar feedback** — on success shows full file path for 4 seconds; on failure shows error message
- All 124 tests pass

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

## BGC-55-56 Delivery Notes (Sprint 6, branch BGC-55-56)

Shipped beyond the ticket spec:

- **Editor UI full redesign** — new header, floating controls, landscape side panel, portrait bottom panel, `_SelectionCard`, `_ActionTile`, animated mode pill
- **Insert mode** — tap palette item to enter insert mode, tap canvas to place symbol at that exact position; tap same item again exits insert mode
- **Bass clef rendering** — `ScoreNotationPainter` now renders F-clef with dots; `StaffPitchMapper` is clef-aware (G/F); key signature accidental positions also clef-aware
- **Eighth note duration fix** — `eighthDuration` was `DurationSpec('eighth', 1)` matching quarter — corrected to distinct value; all DurationSpec constants now: whole=8, half=4, quarter=2, eighth=1
- **`insertSymbolAtMeasureIndex`** — new `EditorActions` method for precise index-targeted insert (used by canvas drop and insert mode)
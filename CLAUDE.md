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

**Current priority (user decision, 2026-11-05):** improve the everyday offline
flow: scan accuracy, easy corrections and reliable playback/save/export.
Start with repeatable real-photo checks and evidence-backed reliability fixes;
do not change the frozen detector or confidence thresholds without validation.
The first slice hardens scan cancellation/retry against stale results and
native model cleanup races (release 2020 verified below). The next slice keeps
the original scan visible during manual correction (release 2021), guided by
real-photo error triage. The current fix lays out sequential scanned rows in
reading order instead of as ensemble columns (release 2022). Guided bar review
now combines automatic photo comparison, direct corrections and saved review
progress (release 2023). Barline geometry now separates missed-note stems from
real boundaries, including boundaries inside loose note boxes (release 2024).
Expanded checks on four additional dataset photos found two real boundaries
falsely rejected by the new attached-head veto, an extra synthesized staff,
and 4/4 read as 44/4. The barline follow-up requires head-sized ink at the
current staff scale and restores the two boundaries in regression tests.
Aligned meter reconstruction now separates an off-column false 4 from the
real 4/4 stack, with ambiguity/multi-digit regression coverage. Merged clef boxes spanning two traced rows no longer add an extra staff, and
new scans keep each row's own bar count instead of padding every row to the
longest. The original three-photo pass is not broad accuracy validation.
Unresolved scan rows now stay together for review with full-width display;
beat counting no longer invents their internal boundaries. Shifted ledger-line
runs now yield to a better supported real staff, restoring the song's missing
barlines without changing the finder thresholds. Beamed-note pitch heads now
use one-ended beam evidence while preserving staff/rhythm association.
Clear beamed heads can now refine their vertical centre from bounded solid ink;
uncertain shapes keep their previous estimate.
Review now offers an explicit previewed key correction across selected scan
rows, keeping later different keys and recording the correction as one edit.
Remaining misclassified/missing-symbol and staff/barline geometry failures are recorded in
`EDITOR_PARITY.md`; full parity stays queued.
Each app change still needs
automated checks and phone QA before
the next feature. Full MuseScore parity remains an explicit
long-term objective in `EDITOR_PARITY.md`; marching templates, family brackets
and the remaining advanced features are deferred, not removed. Symphony's
subjective listening check remains deferred.

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
| ML model | YOLO26n at 960×960 — 24 handwritten symbol classes (model B9 v2 A): clefs, 5 note values, 5 rests, beam, sharp/flat/natural, time-sig digits 2/3/4/6/8, C, cut time, augmentation dot |
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
   For these beamed notes, a detected beam at only one stem end supplies a
   separate metadata['pitchBox'] at the opposite end. Only PitchCalculator
   reads that refinement; suppression, staff/rhythm association and original
   scan boxes keep their prior geometry. A compact, bounded solid-ink component
   can refine that pitch centre; uncertain shapes keep the end-band estimate.
   Ambiguous beams retain the ink guess.
   Staves, in order of preference:
     StaffLineTracer — follows each drawn line across the page (hand-ruled, sloped,
       bent staves); each detected clef picks the five lines it sits on.
       DetectedStaff.offsetAt(x) carries the slope/bend; pitch, staff assignment,
       time-sig digits and the overlay all read the staff where the symbol stands.
     clef-sized level staff (handwritten proportions: G clef 1.48 staves tall, F 0.85)
     projector staves where there is no clef; cluster/synthetic fallbacks after that
   BarlineFinder — thin full-staff-height strokes, excluding horizontal staff
     support, clef boxes and connected note/head/stem ink. Loose note boxes can
     contain an independent barline; uncertain ink keeps the original box veto.
     Strokes must stop at the staff → DetectionResult.barlines
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
   insert notes/rests via Add notes: choose a value, then tap or drag onto the staff
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
                                     note_value.dart (quarterLength: timing from type + dots),
                                     note_beam.dart, beam_grouping.dart (numbered beam boundaries)
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
        widgets/beam_editor_sheet.dart  Measure preview, beam range and beat grouping controls
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
  models/best.tflite                 YOLO26n model B9 v2 A — 960×960 FP32, 24 classes
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

- **Model:** `assets/models/best.tflite` — YOLO26n model B9 v2 A, 960×960 FP32 LiteRT, 24 handwritten classes, trained on stretched grayscale images (data project and training notebooks live outside this repo). SHA-256: `841a0959ac9569bca8f90d151e27b185fa0b495df22a377df640c2379602be76`. Dataset `d0222605`, variant A (1,163 training images), best epoch 65; selected over B using 25 real validation photos. All nine exported evaluations were independently reproduced. Frozen real test AP50 79.92% (B8 80.43%), older real test 95.40%, synthetic test 90.97%; the separate fresh-page AP50 94.25% covers only one page. C/cut time remain synthetic-only in evaluation. Keep the existing confidence cutoffs until validation-based app calibration; detector scores exclude staff filtering and reconstruction. Initialization checks the FP32 tensor contract before decoding.
- **Tiling strategy:** No tiling — full image always stretched to 960×960 (no letterbox, no stave-based cropping). Model was trained on full-page stretches.
- **Staff detection:** `StaffLineTracer` per clef (preferred) → clef-sized level staff → `HorizontalProjectionStaffDetector` where no clef → cluster / `SyntheticStaffBuilder` fallbacks. Competing five-line runs sharing four ordered tracks at a one-line shift use independent-strip support to retain the better-supported real staff, after oversized-staff rejection. A clef box spanning two already traced staff middles does not synthesize another staff; repeated clefs on a recovered row share that row. A staff with no clef of its own is read in the clef of the nearest staff above (else below).
- **Bars:** split at barlines found by `BarlineFinder`; a staff with none keeps its musical symbols together as one `unresolvedBarlines` row for explicit photo review; a meter does not establish boundaries. `ScoreBuilder` retains each scanned row's own bar count. The sequential display projection supplies hidden layout cells without saving artificial bars; imported ensembles retain their separate layout.
- **Engraving:** Stage 4I EngravingLayout / BarPlacement shares rational onset positions across screen, PDF, hit targets, lyrics/text, insertion and playhead. Duration springs, compact grace clusters, aligned staves/voices, chord-second head displacement/shared stems, accidental columns and ledger lines. Text/lyrics reserve ink bounds; simultaneous text stacks; note/stem/mark headroom moves text/lyrics and staves apart. Score-wide density chooses up to four equal-width bars per row; oversized logical pages fit uniformly onto A4. Automatic overflow pages retain explicit breaks; longest-staff layout slots keep uneven ensembles visible. Geometry/policy cache by immutable score; saved models/audio unchanged. Remaining optical engraving, variable-width bars, system locks, advanced collisions and cross-staff work are in EDITOR_PARITY.md; next is 5C new-score wizard.
- **Notation renderer:** CustomPainter — not a text list, not an SVG library. Editor and PDF follow the same rules: the key signature starts every row; the time signature shows on a page's first measure and wherever it changes (before the row's opening barline when the key leaves room, else inside the measure, whose notes move right; `ScoreNotationMetrics.timeSignatureInMeasure`). Flags are solid and point right on up and down stems; beamed eighths and sixteenths are drawn with beams (a chord tone neither joins nor ends a group).
- **Undo/redo:** Whole-state snapshot, max 50 entries, new edit clears redo stack
- **Note values:** the editor offers the scanner's ten values: whole, half, quarter, eighth and sixteenth notes and rests (palette, DURATION tab, drawing in editor and PDF). A symbol's stored `duration` counts 2 divisions per quarter, which cannot hold a sixteenth or a dotted eighth, so all timing (playback, MusicXML `<duration>`, measure-full checks, genre model) uses `quarterLength(type, dots, duration)` from `lib/core/models/note_value.dart`. Chord tones take no time in a measure.
- **Hidden, not removed:** `AppFeatures` (`lib/core/config/app_features.dart`) switches off features the presentation build does not show: `classroomWorkflow` (teacher/student), `legacyScoreLabels` (the old rule labels), `cClefs` (alto/tenor clef tiles; the scanner reads G and F clefs only).
- **Transpose:** More → Transpose… (and command search) opens `TransposeSheet`: to a key, by interval or diatonically, as MuseScore's dialog; `Transposer` moves sounding pitch and rewrites accidentals for the new key; whole score, one undo step. Checked against MuseScore `--transpose` output in `test/musescore_parity` (`transpositions.json`).
- **Range selection & clipboard:** `EditorState.rangeAnchor` + selection form a range in one part (dropped by any edit/undo/plain selection). Shift+←/→ / Shift+tap / Ctrl+Shift+←/→ / Ctrl+A; Edit dock Extend, Select bar, Copy, Cut, Paste. Paste is bar-aligned, replaces a range, refuses overflowing bars, strips review IDs. Pitch/octave moves and Transpose apply to a range.
- **Voices:** `VoiceLayout` aligns voices by onset in editor and PDF (odd voices stem up, even down; rests offset); single-voice bars unchanged. Add notes Voice 1–4 chips / Ctrl+Alt+1–4; a new voice starts at the selected note's onset, filling earlier time with rests.
- **Staves and instruments:** More → Staves and instruments… (`StavesSheet`) adds/renames/reorders/removes parts via `rearrangeParts` (one undo step); new staves copy bar structure and switch playback to simultaneous parts; refused for multi-staff scanned scores (sequential reading order).
- **Grand staff:** `Part.staff` > 1 makes a part a further staff of the part above (linked parts, braced, barlines through both). MusicXML import splits `<staves>` parts (ids `P1`, `P1-staff2`; bindings keep the source part id; the timeline reads source events per staff); export merges them into one `<part>` with `<staves>`, numbered clefs, `<backup>`, and voices 5–8 for staff 2. Staves sheet adds Piano as a grand staff; a lower staff moved away from its upper staff becomes independent.
- **Ties and slurs:** `Score.spanners` (kind + review IDs of the end notes, `lib/core/models/spanner.dart`; `SpannerIndex` resolves live ones). Imported/exported as MusicXML ties and numbered slurs; tied notes play as one; + ties (note entry: adds a tied note), S slurs; drawn in editor and PDF. A spanner change makes an imported file rebuild from the model instead of patching.
- **Tuplets:** `Tuplet` (actual:normal, bracket start/stop) on `Note`/`Rest`; all timing goes through `symbolQuarters` / `ScoreTimelineBuilder.writtenDuration`. Copy notes with `copyWith` (never field by field). Ctrl/Cmd+3/5/6/7 or the Triplet tile make a tuplet; note input types over its rests. MusicXML export raises `<divisions>` for tuplets.
- **Articulations and ornaments:** `Note.marks`/`Rest.marks` (`Articulation` enum, fixed order); MusicXML import/export; playback lengths and ornament patterns as MuseScore plays them; Shift+S/N/V/O and the Edit-dock Marks row toggle across the selection; shapes shared by editor and PDF in `mark_glyphs.dart`.
- **Dynamics and hairpins:** `Note/Rest.dynamicMark`; hairpins are crescendo/diminuendo spanners. MusicXML `<direction>` import/export (wedge stop after the last note). Playback velocity per event matches MuseScore (mf 80 default; p 49 … ff 112; sfz stresses one note; hairpins glide, truncated; accents one level up). < / > and the Edit-dock Dynamics row. Parity tests compare velocities.
- **Lyrics:** `Note.lyrics` (`Lyric`: verse token, text, syllabic state, melisma start/continue/stop, placement/visibility); project JSON and MusicXML both ways. Imported lyric XML keeps rich text/elisions/metadata. Lyric-only changes patch retained MusicXML; modeled lyrics do not block generated rhythm export. Edit → Lyrics / Ctrl/Cmd+L / command search opens a draft panel: Space advances words, - syllables, _ extensions; paste fills notes in the selected voice/staff, skipping rests/chord tones/tied continuations (extensions include ties). Apply is one undo step; Cancel has no effect. Shared `LyricLayout` draws verses, hyphens and split extension lines in editor/PDF; lyric text selects its note. `EditorLayoutPolicy.forScore` reserves verse height and matches PDF pagination. Stage 4E checkpoint in `EDITOR_PARITY.md`; next is 4F text/tempo/chord symbols.
- **Text, tempo and chord symbols:** `Measure.annotations` (`ScoreAnnotation`: kind, exact quarter offset, text, metronome unit/dots/BPM, `ChordSymbol`, staff, retained XML/source index). Edit → Text & tempo, command search, Ctrl/Cmd+Alt+T/K; draft Apply is one undo step, Cancel is inert. Beat numbers follow the meter. Source directions/harmonies patch safely, retaining unrelated notation; simple modeled documents also rebuild after rhythm edits. Generated system directions require MusicXML 4.0 (ordinary output 3.1; rebuilt 4.0 sources stay 4.0). `AnnotationLayout` shares screen/PDF placement and selection, with system text/rehearsal/tempo on the top staff. `TempoMap` integrates written tempos, repeats, held notes, ensemble and sequential scan timing; marked scores show relative transport speed (120 = 100%). Common chord kinds/slash basses play piano voicings; transpose moves roots/basses. MuseScore `12_text_chord_symbols`: notation 21/21, playback 51/51. See Stage 4F checkpoint.
- **Repeats, endings and jumps:** `Measure.endingStart`/`endingEnd`, `Measure.navigation` (`NavigationMark`: segno, coda, Fine, To Coda, D.C./D.S. and al Fine/al Coda) and `BarlineType` double/final. `ScoreTimelineBuilder.playOrder` unrolls them for playback as MuseScore does (repeat count = highest ending number; no repeats after a jump). MusicXML import/export both ways; Bar tools → Repeats and command search toggle them on the selected bars in every staff (one undo step); editor and PDF draw them via `barShapes`. MuseScore imports D.C./D.S. from MusicXML as text, so their parity cases are `.mscx`.
- **Bar rests, pickups, common/cut time:** `Rest.measureRest` (`<rest measure="yes"/>`, drawn as a centred whole rest; a new length makes it ordinary), `Measure.implicit` (pickup: left out of the bar count, numbered 0 at the start and unlabelled; renumbering keeps the count), `TimeSignature.symbol` (`TimeSymbol.common`/`cut`, drawn C/¢; scans keep it). Bar tools → Measures → Pickup / Bar rest, Time → C / ¢, and command search. MuseScore `01` and `03` match fully.
- **Grace notes:** `Note.grace` (`Grace.appoggiatura`/`acciaccatura`) takes no bar time; MusicXML `<grace>` both ways (no `<duration>`, grace beams kept); playback borrows one grace value (≤ half the lender) from the main note's start (appoggiatura) or the previous note's end (acciaccatura), as measured from MuseScore in `19_grace_timing`. Edit → Acciacc./Appogg. and search add one before the selected note. Drawn at `graceScale` (65%), slashed for acciaccatura. Stage 4H checkpoints in `EDITOR_PARITY.md`; Stage 5A mixer is complete, next is 4I engraving.
- **New-score wizard:** Collection → + → New Score opens `NewScoreWizard` (instruments: your staves or MuseScore-style templates; then title, composer, key, time incl. C/¢, pickup, bars (32), optional tempo). `buildNewScore(NewScoreOptions)` in `lib/features/new_score/new_score.dart` is the testable core; templates (26, incl. jazz combo, big band, concert bands, Classical/Symphony/String orchestra) match MuseScore's part names, programs and clefs (`new_score_test.dart`, references in `test/musescore_parity/reference/templates/`); `NewStaff.program` overrides a staff's sound; `instrumentKey(name)` strips part numbers ("Horn in F 1 & 2") for `transpositionFor`/`defaultProgramFor`. `NewStaff.lowerClef` adds an independent second staff: Classical orchestra has 12 instruments / 13 staves, including two treble horn staves with shared sound/transposition and a square bracket (`Part.squareBracket`, JSON, canvas/PDF and MusicXML). It uses eight pitched MIDI channels. `Clef.octave` (clef-octave-change) supports treble 8vb for tenor/guitar: pitch stays sounding, `Clef.layoutSign` (`G-1`) shifts staff position. Stage 5C in `EDITOR_PARITY.md`.
- **Transposing instruments:** `Part.transposition` (MusicXML `<transpose>`; notes/keys stored as written, playback adds the interval). `Score.concertPitch` + `Transposer.concertPitch` (More → Concert pitch, one undo step; export always writes players' parts). `transpositionFor(name)` gives MuseScore's transpositions (B♭ clarinet/trumpet, E♭/B♭ saxes, horn in F, octave basses). Copy parts with `Part.copyWith`, never field by field. Stage 5D part 1 in `EDITOR_PARITY.md`.
- **Drums:** `Clef.percussion` staff (`Part.isPercussion`, no key, notes placed as treble); `Note.drum` (GM key) + `Note.notehead`; `drumKit` gives MuseScore's positions/voices/letters (A–H). MusicXML `<unpitched>` + `<instrument>`/`<midi-unpitched>` both ways; channel 10 playback; transpose skips drums. Add notes shows kit buttons on a drum staff. `Part.staffLines`/`Part.drumMap` retain one-line snare, bass-drum and cymbal maps (JSON, input, canvas/PDF and MusicXML). Playback selects SoundFont bank 128 for channel 10; the mixer offers the bundled kit names and shares kit/volume/pan across percussion parts, keeping mute/solo per part. Stage 5D part 2 in `EDITOR_PARITY.md`.
- **Tablature:** `Clef.tab` staff (`Part.isTab`, `Part.tabTuning` lowest string first) with `Note.string` (1 = highest) / `Note.fret`; pitch stays sounding. MusicXML `<staff-details>` tuning and `<technical>` string/fret both ways, no accidentals on TAB. `placeTabNotes` (in `_updateState`) keeps strings/frets in step with pitch. Fret numbers drawn on string lines in editor and PDF; simple TAB hides rests and time signatures in both, including meter changes. Stage 5D part 3 in `EDITOR_PARITY.md`. Guitar + tablature: `Part.linked` TAB staff mirrors the staff above (`syncLinkedStaves` in `_updateState`, copies whichever side was edited, keeping each staff's IDs/voices/clefs); only the upper staff plays; import links a TAB staff that repeats the staff above (MuseScore writes linked notes twice); template, Staves sheet "Guitar + TAB"; `27_guitar_and_tab` parity.
- **Cross-staff notes:** `Note.staffMove` (±1) draws a note on the neighbouring staff of its instrument while it keeps its own staff's voice and time; MusicXML `<staff>` = home + move. Import picks each voice's home staff by majority (`homeStaves` in `musicxml_source.dart`, also used by the source timeline). Ctrl/Cmd+Shift+Down/Up and Edit-dock Staff down/up. Stage 5D part 4 in `EDITOR_PARITY.md`; the agreed MuseScore stage list is complete.
- **Selection after edits:** `_updateState` re-resolves the selected symbol by position after `NotationReviewService.ensureIdentity` (which rebuilds symbols).
- **Note entry:** the editor dock has Edit, Add notes and Bar tools modes. Add notes starts with a quarter note ready to place; Notes/Rests switches preserve the duration. Pick one of five values and tap the staff or hold and drag a palette symbol. Re-selecting a value keeps note entry active; Edit or Esc finishes. Keyboard (MuseScore-style): A–G writes a note (nearest octave), 0 a rest, writing over what follows in the voice (a selected rest itself; values too long for the bar are tied into the next; `_overwrite` in editor_actions; tap/drag onto the staff still inserts). Split notes keep sounding accidentals across bars/key changes; 32nd remainders are exact and drawn with three flags/beams or the 32nd rest glyph; finer unrepresentable splits leave the score intact. Playback holds whole tie chains. Add notes → Chord adds an exact tapped pitch above/below the selected note in its bar; Insert or Ctrl/Cmd+Shift+A–G shifts later music within the current bar and can lengthen it beyond the meter (no automatic rebar). Complex retained-source insertions are refused. Outside note entry A–G re-pitches the selection; Shift+A–G / Alt+2–9 add chord tones. `insertNoteAfterSelection()` / `insertRestAfterSelection()` remain domain helpers.
- **Drag insert:** LongPressDraggable from palette → DragTarget on staff. Drop Y → pitch via PitchCalculator. Drop X → insert index.
- **PDF export:** `pdf` package with programmatic Canvas drawing — replicates CustomPainter logic. `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled.
- **MusicXML export:** `xml` package, MusicXML 3.1 (4.0 for system directions or rebuilt 4.0 sources). `exportToDevice(Score)` opens system save dialog via `file_picker` — returns saved path or `null` if cancelled. Writes 8 divisions per quarter with each `<duration>` from the written type and dots, and spells a sixteenth `16th`. Writes `<accidental>` from `Note.alter` and `<backup>`/`<forward>` between voice/staff lanes. Exports `<print new-page="yes">` and `<print new-system="yes">` from `Measure.startsNewPage` / `startsNewSystem`. Exports numbered `<beam>` boundaries (begin/continue/end) and secondary forward/backward hooks through `BeamGrouping.valuesFor`.
- **MusicXML import:** `ImportScoreScreen` uses `MusicXmlImporter`: one system picker showing all files (a filtered picker greys out .musicxml/.mxl on Android), then the extension is checked; reads .xml, .musicxml and .mxl (the file `META-INF/container.xml` names), UTF-8, UTF-16 or Latin-1. Reads `<print new-page="yes">` → `Measure.startsNewPage` and `<print new-system="yes">` → `Measure.startsNewSystem`. Normalizes `<duration>` values from any `<divisions>` setting to the internal 2-divisions-per-quarter convention. A note or rest without `<type>`, and every whole-bar rest (`<rest measure="yes"/>`), takes its value from its duration (a 3/4 bar rest becomes a dotted half). A `16th` is stored as `sixteenth`, as scans write it. `Note.beams` preserves numbered beam boundaries and hooks, keeping adjacent groups distinct through save/load, preview and export. Older projects containing only `beamed` remain supported. The preview shows page 1 as the editor lays it out (`ScorePageThumbnail`).
- **Imported layout preservation:** Explicit page breaks (`startsNewPage`) start a new editor page; scores without them fall back to the 4×5 grid. System breaks (`startsNewSystem`) are kept through edits and written back on export, but the editor grid does not break rows at them. Reflow (resetting breaks) is deferred to Milestone 5.
- **Audio playback:** `flutter_midi_pro` — synthesizes from Note step+octave+duration directly. Requires `assets/soundfonts/piano.sf2` (any standard GM SF2 file, not committed). After adding the file run `flutter clean && flutter pub get` then do a full restart (not hot reload) to rebundle assets.
- **Score label (genre):** the app shows only Waltz, Kundiman or Jazz (null for a score without notes): on score cards, in the editor header (worked out 600 ms after edits stop) and on the scan result screen. `ScoreClassifier.classify` asks `GenreModel` (LSTM, loaded in `main`) first and uses its answer when at least 0.7 sure of one of the three. Otherwise (it says "other", is unsure, has under 16 notes, or is not loaded) `classifyByRules` picks one of the three (a rule Kundiman also needs the model's kundiman ≥ `minRuleKundiman` 0.4 when the model ran, else Waltz; `ScoreClassifier.decide` is the testable core): not triple time → Jazz; triple time (3, 6 or 9 beats) → Kundiman when the first half of the melody is in a minor key (Krumhansl–Schmuckler), else Waltz. The old labels live on in `classifyByLegacyRules` behind `AppFeatures.legacyScoreLabels`. `GenreModel.features` must match `features()` in the data project's genre_train.py.
- **Review & Correct (paper Objective 3):** the editor has a visible review button and an automatic reminder after scans; the overflow menu also retains "Check Notation". `NotationReviewPanel` stays beside the score on wide screens and below it on phones (resizable). On compact or large-text layouts its header, comparison choices and actions scroll together so Apply remains reachable; comparison choices wrap as needed. Selecting a finding focuses its measure; the canvas remains pannable/zoomable, with editing available via "Edit manually". Each suggested change requires a current/proposed preview; batch review applies only explicitly selected, still-valid suggestions as one undo step. Dependent suggestions are rechecked and omitted when their context changes. `NotationReviewService` assigns stable measure/symbol IDs, records applied/kept decisions, rejects stale previews, and supports conflict-checked restore from History. Decisions and scan evidence live in `Score.reviewHistory` / `sourcePages`, travel through project save/export, and participate in undo/redo. Original scan crops come from normalized symbol bounds retained by the mapper; `ScoreSourceService` compresses an orientation-corrected page once per scan, fully offline. Older projects and MusicXML work without source images. Passage audition uses the same tempo for current/proposed notation, stops at the affected range, and cancels pending playback when review closes. The checker still covers uncertain recognition, missing components, redundant accidentals, beat totals (pickup exempt), and meter mismatches; mathematical consistency is presented as a suggestion requiring musical judgment. A short or overfull bar is never padded with rests or fixed by shortening its last note: on 54 real test photos (`tool/real_scan_review_eval_test.dart`) those fixes moved most bars further from the page, because the model had missed or misread a note; such bars are listed for the user to check ("A note may be missing"). The remaining fixes (repeated detection, notes moved across a barline, bar split, meter, redundant accidental, beam to flag, clef) never change the notes; `test/core/services/notation_checker_real_scan_test.dart` checks this on six real scans. Tests: `notation_review_service_test.dart`, `score_source_service_test.dart`, `review_playback_test.dart`, `notation_review_workflow_test.dart`. Set `NV_REVIEW_SCREENSHOTS=/tmp/note-vision-review-screenshots` when running the workflow test to render phone/tablet comparisons.
- **Save/load:** JSON files in app documents directory via path_provider. Project index in shared_preferences. The editor compares the current score with the last saved snapshot, so undo/redo and edits during an asynchronous save retain an accurate Unsaved indicator. Save is disabled while saving, with visible progress.
- **Export filename:** shared `safeExportFileName(title)` in `lib/core/utils/export_file_name.dart`.
- **Delete symbol:** the contextual Edit header has a visible Delete symbol button; Delete/Backspace also removes the selection. Holding and dragging a symbol reveals a trash target in the control dock on phones, or on the canvas beside the controls on wider screens. All deletions can be undone.
- **Clear all symbols:** More → Clear all symbols… confirms the number of notes/rests across every page and staff. It preserves measures, page/system breaks, clefs, signatures, barlines, score details, scan evidence and review history. Clearing is one undo step, preserves measure context, resets paused playback and stale review previews, and offers an Undo banner. It is disabled during playback/loading and when already empty, and hidden in read-only review mode. Cancel or dismissal makes no changes. Tests: `clear_all_symbols_test.dart` in editor domain and presentation.
- **Editor layout and controls:** document actions stay in the header (Review is labeled); a separate navigation row shows staff/bar context, pages and an Editor guide. The contextual `EditorToolDock` sits below the paper on phones and beside it on wide/short screens. Edit exposes duration glyphs, dots, beams, pitch and accidentals together; its header has Delete and previous/next symbol buttons. Navigation skips empty bars, follows page breaks, and never adds undo history. Bar tools groups measure actions, time and clef settings. Controls scroll independently for small screens and large text. Initial fitting shows the whole page; Fit page and Focus selected bar are separate actions. Zoom clamps to 15–500%. Initial selection survives review-ID assignment. Ctrl/Cmd+Z, Shift+Ctrl/Cmd+Z, Ctrl/Cmd+S, arrows, N, Esc, Delete/Backspace and Space support keyboards; modal dialogs, text input, review and playback locks protect editing. Tests: `editor_controls_test.dart`, `editor_workspace_test.dart`; `NV_EDITOR_SCREENSHOTS=/tmp/note-vision-editor-controls` renders phone/tablet and mode comparisons.
- **Phone editing dock:** Edit/Add notes/Bar tools stay in a fixed mode strip while the contextual body scrolls. The canvas remains pannable and editable above it; tool changes do not open a barrier over the music. Bar tools → Time sets 2/4, 3/4, 4/4, 2/2, 3/8 or 6/8 at the selected measure in every part. Time and clef scope are described beside their controls. Pitch needs a note; duration/dot actions reflect measure capacity. Mode, palette, duration, accidental and staff choices expose accessible activation and selected states.
- **In-project scan:** "Scan Page" icon button (`Icons.add_photo_alternate_rounded`) in `_EditorHeader`, disabled during playback. Tapping shows a bottom sheet (Camera / Gallery), picks image, then pushes `ScanScreenProvider(appendMode: true)`. On "Continue", `ScanScreen` pops with the scanned `Score` instead of pushing `EditorShellScreen`. The editor merges parts by index (min of current vs scanned part count), renumbers all measures, pushes to undo stack, and jumps to the last page.
- **Scan preferences:** `ScanPreferencesService` stores two booleans in SharedPreferences (`scan_skip_preview`, `scan_skip_review`, both default `false`). Toggles live in a "SCAN SETTINGS" section at the bottom of `ProfileStatsScreen`. Skip-preview skips the image preview in `CaptureScreen` and goes straight to scanning. Skip-review auto-advances past the detection results screen in `ScanScreen` when detections are found (guarded by `_autoNavigated` flag to prevent double-fire).
- **Playback controls:** `PlaybackControlsBar` uses the editor's injected service and a native accessible measure slider, with 48 px transport/tempo targets. Small screens and large text use two rows. The scrubber follows actual staff lengths. Seeking while stopped or paused cues silently; Resume rebuilds events from current edits while retaining the cued symbol when its ID survives. Loading can be cancelled with Stop, and errors expose Retry. `editor_controls_test.dart` covers layouts, semantics, transport, and save state; set `NV_EDITOR_SCREENSHOTS=/tmp/note-vision-editor-controls` to render snapshots.
- **Playback lock:** all editor interactions (symbol tap, drag, palette, insert mode, inspector tiles, undo/redo, metadata) are disabled during loading and `PlaybackStatus.playing`. Pan/zoom is unaffected. `paused` leaves interactions enabled so the user can edit between playback sessions.
- **Instrument sounds and mixer:** More → Mixer…, command search or F10 opens a draft panel with 128 GM bank-0 sounds, volume (0–100%), stereo pan, mute and solo. Apply is one undoable edit; Cancel/dismiss has no effect. `Part.playback` (`PartPlayback`) saves settings in project JSON; old projects retain piano. Linked grand-staff parts share a strip; sequential scanned lines share one strip. New staves get their usual sound; renaming does not change it. Playback uses separate pitched MIDI channels (15 sounding instruments, channel 10 reserved; instruments with identical settings share one, so a concert band fits), CC7/CC10 and channel+pitch note-off counts. Changes apply on play/resume, with cancellation and errors handled while configuring sounds. Single initial pitched MusicXML instrument programs/volume/pan import and export; edits patch retained declarations without changing instrument IDs or unknown notation. Mute/solo are project-only. Complete GM SF2 required at the historical `assets/soundfonts/piano.sf2` path. Stage 5A details and limitations in `EDITOR_PARITY.md`; next is 4I proportional spacing and collisions.
- **Beam editing:** Edit → Beams or Bar tools → Measures → Beams opens a measure preview with sticky notation above scrollable phone controls. Tap first/last eligible notes to select a range, then Beam together, Separate notes, or Break before/after the focused note. Group by beat handles simple/compound meters and aligns a short opening pickup to the end of its measure; additive meters such as 5/8 keep manual grouping. Rests, longer notes and voice/staff boundaries prevent joining; chord tones do not interrupt a group. Apply commits the complete preview as one undo step; Cancel and Reset leave the score untouched. Structural edits repair explicit beam boundaries; ordinary pitch/accidental/dot edits preserve imported evidence. `BeamGrouping` is shared by the editor, checker, canvas, PDF and MusicXML export. Tests: `beam_grouping_test.dart`, `beam_editor_test.dart`, `explicit_beams_test.dart`; set `NV_EDITOR_SCREENSHOTS=/tmp/note-vision-beams` for phone, large-text, landscape and tablet snapshots.
- **Playback page auto-advance:** `positionStream` from `PlaybackService` updates `_currentPageIndex` in `_EditorShellScreenState` when the page index derived from `EditorLayoutPolicy` changes. Viewport zoom/fit is NOT reset on playback-driven page changes (only on manual navigation).
- **Smooth page transition:** `AnimatedSwitcher` (250ms crossfade) wraps the white-sheet `Container` inside `InteractiveViewer`, keyed by `pageFirstMeasure`. Triggers on both manual and playback-driven page changes.
- **Cross-measure/part drag reorder:** `moveSymbolToDest()` in `editor_actions.dart` — same-measure delegates to `reorderSymbol`; cross-measure deletes from source + inserts at destination; cross-part supported.
- **Collection = project list:** `CollectionScreen` owns both the scan history and the saved project list. `ProjectListScreen` was deleted; `/projects` route removed.
- **Analytics:** Local only — scans, edits, exports, playbacks as integers in shared_preferences. No backend.
- **Username:** Name + profile photo. First-launch onboarding. Stored locally.
- **App is fully offline:** No network calls, no auth, no backend, ever.
- **noteheadBlack fallback:** When YOLO misses the stem of a black notehead, the note is assumed quarter rather than dropped. Priority: (1) stem + flag/beam → eighth, (2) stem only → quarter, (3) beam but no stem → eighth, (4) no stem/beam → quarter.
- **Multi-page rendering:** Editor splits the score into pages via `EditorLayoutPolicy` — EditorLayoutPolicy.standard sets a maximum of 4 measures per row × 5 rows; forScore reduces density and row count for engraving width/headroom (Stage 4I). `_currentPageIndex` lives in `_EditorShellScreenState` (not `EditorState`) so undo/redo don't change pages. `ScoreNotationViewer` accepts `firstMeasureIndex` + `pageMeasureCount` to slice measures; `_NotationAreaState` translates all interaction indices (tap, insert, drag, drop) between page-relative and absolute. Measure prev/next navigation auto-switches pages at boundaries. Explicit page breaks are retained, with extra automatic pages when a section exceeds capacity.

---

## EditorState — How It Works

**Bar assignment reliability (2026-11-05):** `BarlineFinder` ignores horizontal
staff ink when measuring vertical coverage, rejects attached heads on missed
notes, and traces connected ink inside loose note boxes so a neighboring real
barline is retained. The paired photo's first bass row changes from detected
note counts **[1, 2, 17] to [3, 9, 8]** on the phone (**[3, 8, 9]** in
the frozen local-runtime replay, whose detected notes differ slightly). Its
source first bar has five heads; two remain missed by the unchanged model.
Applies to new scans; saved music is not reparsed. Three native Android
picker-prepared regression photos cover
22 staves / 45 checked interior boundaries; mixed/dense score contents stay
identical in replay and every detected note/rest stays in order. Android's
Bitmap resize/JPEG input differs from older tools' Dart linear approximation;
use committed `test/fixtures/barlines` for exact replay. **1,070 tests passed**,
analysis clean. Physical **2024** QA freshly scanned all three photos:
paired boundaries improved with all 139 note contents/order retained;
mixed/dense musical MusicXML stayed identical, with one-page editor/PDF output
for all three. Existing mixed/dense scores export byte-identically after the
update, and mixed review retains 18 pending bars + one deferred. Evidence:
`/tmp/note-vision-phone-2024/`; device checkpoint in `EDITOR_PARITY.md`.
Recognition of meter/key, chords and joined note/barline ink still needs work;
full parity remains queued.

**Expanded scan QA (2026-11-05, unchanged release 2024):** four additional
dataset photos were freshly scanned on the Realme (sparse exercises,
clef-writing negative control, song with lyrics, uneven exercises). Two real
barlines are newly rejected by the attached-head check: `211244_372` row 7
x≈353 and `211432_497` row 4 x≈743 at 904×1200. These were unfixed at that
checkpoint; the 2026-11-06 follow-up below addresses them. Other failures
include eight visible staves
becoming nine, 4/4 read as 44/4, the song's second row losing both boundaries,
missed rests, and beat fallback padding every part to seven or 21 bars. The
one-page PDFs become crowded with tiny notation and empty bars. The clef-only
page correctly exports zero notes/rests and disables playback/PDF. See
`EDITOR_PARITY.md` for exact cases; evidence:
`/tmp/note-vision-extra-images-2024/`. The earlier 1,070 passing tests and
three-photo check do not cover these failures; no model tuning or app changes
were made in this QA pass.

**Barline regression follow-up (2026-11-06):** head veto requires consecutive
broad ink spanning a third of a staff space with a peak width over half a space,
plus existing stroke guards. Small staff-line fragments and neighboring-head
edges no longer hide sparse row 7 (x≈353) or uneven row 4 (x≈743). Tapered heads
still qualify; the paired sheet's missed-note stem remains rejected. All seven
native-prepared photos are committed with frozen detections: original three
expectations remain intact, both added boundaries return without losing or
reordering detected note/rest IDs, and song/clef-control score JSON is unchanged.
The expanded inputs retain known detection errors; they are not complete ground
truth. **1,077 tests passed**, including 16 focused cases; analysis clean. Four
regressions fail against the previous finder. No model/threshold changes or
saved-score migration. Extra staff, 44/4, missed song bars/rests and padded-bar
layout remain separate work. Physical release **2025** freshly scans both
affected sheets and the original paired control: both boundaries return in
the overlay and MusicXML, with all detected note contents/order retained.
The paired row stays [3,9,8] and all 139 notes remain unchanged. Cold restart
retains all 22 original projects plus three new QA scans; sparse/uneven cold
exports and the original saved paired score are byte-identical. Phone settings
restored and temporary helpers removed. Evidence:
`/tmp/note-vision-barline-regressions-2025/`; device checkpoint in
`EDITOR_PARITY.md`.

**Meter reconstruction follow-up (2026-11-06):** `SignatureInferrer` selects
centered upper/lower digit runs instead of concatenating all detections on
each row. The sparse photo's off-column false 4 no longer creates 44/4;
warnings record ignored digits or unresolved competing stacks. Real multi-digit
meters (including centered 44/4), C/cut time and staff slope remain supported.
Missing rows are not borrowed from another exercise or inferred from beat
totals. Seven-photo before/after JSON replay changes only three inherited
P1 numerators 44 → 4; all other score data and the other six cases are identical.
**1,101 tests passed**, including 24 focused cases; analysis clean. The model,
confidence cutoffs, key/staff inference, beat fallback and existing project
files are unchanged. Extra staff, misclassified/missing symbols (including the
mixed sheet's 3/4 read as 2/4), missed song boundaries and padded-bar layout
remain queued alongside full parity. Evidence:
`/tmp/note-vision-meter-2026/`; checkpoint in `EDITOR_PARITY.md`. Physical
release **2026** freshly scans sparse and uneven sheets: sparse PDF/MusicXML
shows 4/4, changing only three numerator fields; all music/key/bar contents
remain identical, and the 4/4–2/4 uneven control is unchanged. The corrected
sparse export survives cold reopen byte-identically. All 25 original projects
remain (27 with two new QA scans), and the original saved score exports
byte-identically after installation. Phone preferences restored; helper removed.

**Staff and bar-count follow-up (2026-11-06):** clef fallback rejects a box
spanning two traced staff middles at the clef's own x (including slope), and
checks already synthesized rows before adding another. New scans retain natural
per-row bar counts; the reading-order projection already handles uneven rows
with hidden display cells. Genuine empty bars remain. Frozen seven-photo replay:
sparse **9 → 8** staves and **63 → 24** stored bars; uneven **126 → 37**,
song **35 → 19**, mixed **24 → 19**. Every detected note/rest ID and duration
survives. Ten sparse bottom-row pitches now follow the real traced staff instead
of the giant false staff; the other six scans' musical symbols are identical.
Three staff regressions and the old padding expectation fail before the fix;
five focused reconstruction cases pass afterward. Full **1,105 tests passed**,
analysis clean. Model/cutoffs and beat fallback are unchanged; the uneven row
with no reliable boundaries still produces 21 bars. Existing saved projects are
not trimmed or reparsed. Full parity remains queued. Evidence:
`/tmp/note-vision-staves-2027/`; device checkpoint in `EDITOR_PARITY.md`.
Physical release **2027** confirms sparse **175 symbols / 8 staves / 24 bars**
and uneven **133 symbols / 6 staves / 37 bars**. Both retain all notes/rests;
only ten sparse bottom-row pitches change. PDFs show eight and twelve visual
rows respectively, with no artificial trailing bars. A new five-staff photo
from the dataset saves/exports five rows of three bars. All three new scans'
cold MusicXML exports are byte-identical; collection count **27 → 30**.
Uneven playback reaches its last row/bar (**37/37**) and Play/Stop works.
The originally open paired score exports byte-identically before/after the
update and is restored saved/stopped. Retained logs show no Flutter/crash/save
errors; phone preferences restored and temporary helpers removed. Requested QA
photo copies remain, and exports are in `Download/NoteVisionQA2027/`.

**Unresolved scan rows (2026-11-06):** the uneven sheet's last two rows have
no drawn internal barlines. `MeasureGrouper` keeps each complete row together,
with persistent `Measure.unresolvedBarlines`, instead of partitioning by assumed
beat capacity. Ordinary barline-based reconstruction is unchanged. Review says
"Barlines unconfirmed", keeps the photo comparison, and asks whether this is an
unbarred exercise or a missed line; it offers no guessed split or beat-total
fix for that row. Existing Keep/Review later decisions still apply.
The display projection gives the row all layout columns without adding musical
bars. Shared engraving, canvas, PDF, hit/input targets, playhead and review focus
use that width; unconfirmed rows have no invented bar numbers/end strokes.
Note entry, duration changes and drag/drop use the actual row contents rather
than a nominal single-bar capacity, preserving the written meter and undo.
Frozen seven-photo replay: uneven **37 → 13** stored groups (**[2,2,3,4,1,1]**),
song **19 → 13** (**[3,1,3,3,3]**); every note/rest JSON is identical. These totals
include unresolved rows, not 13 verified written bars. The other five scores are
identical. Existing projects are not reparsed or migrated. JSON/project storage
retains the flag; ordinary MusicXML keeps the full sequence in one measure and
its written meter, without NoteVision's review flag.
The song's actual missing boundaries remain a separate geometry issue: its
second staff trace ends near x266, limiting the finder to x311. A diagnostic
wider search sees the first written boundary at x343, while x612 is still
rejected because the extrapolated staff top drifts. Do not solve this by
loosening confidence or accepting note stems. **1,115 tests passed**, analysis clean. Evidence:
`/tmp/note-vision-boundaries-2028/`; checkpoint in `EDITOR_PARITY.md`.
Physical release **2028** confirms uneven **96 notes**, **[2,2,3,4,1,1]**
stored groups and a six-row one-page PDF. After cold reopening, its fifth
row still shows "Barlines unconfirmed" and the explicit source-comparison
warning without a split proposal. Playback works on that 21-note row. Song
retains **92 notes / 10 rests**, **[3,1,3,3,3]** groups and five visible PDF rows;
physical note/rest content matches its earlier baseline. Sparse control retains
137 notes / 8 rests, byte-identical MusicXML and pixel-identical PDF to release
2027. All three new scans reopen with byte-identical XML; collection **30 → 33**.
The song's true missed boundaries remain queued. Original paired score exports
byte-identically before/after installation and is restored saved/stopped.
Retained logs show no Flutter/crash/save errors. Original phone preferences are
restored; temporary helpers removed and requested recent test copies retained.
QA exports: `Download/NoteVisionQA2028/`; facts/hashes in the work directory.

**Shifted staff runs (2026-11-07):** the song's short second-row trace was
one staff line too low: four real tracks plus a ledger line. It fit the detected
clef slightly better than the real candidate. `StaffLineTracer` now retains
track identities per line across joined fragments. Of two eligible five-line
runs sharing four ordered tracks at a one-line shift, the run seen in more
independent strips wins; ties retain the previous clef-based choice. Existing
oversized-staff rejection runs first. No clef/barline thresholds or model
weights change. The real trace reaches x654 instead of x266; both written
boundaries near x343/x612 are detected by the unchanged finder, with the
misleading x241 stem still rejected when its note detection is removed.
Frozen full-output replay: song **[3,1,3,3,3] → [3,3,3,3,3]**; all detected
note/rest IDs, order and lengths stay unchanged. **31** second-row pitches now
use the real staff geometry (first ledger note **E4 → C4**, visually checked).
Other notehead-localization/recognition errors remain; this is not a complete
transcription oracle. All six other frozen scores are identical. Old saved
projects are not reparsed. Four new tests cover ledger runs above/below, a
genuinely short independent staff, and the real song's boundaries, note values
and ledger C4. Two initial cases failed before the fix. Full **1,119 tests
passed**, analysis clean. Evidence: `/tmp/note-vision-trace-2029/`; checkpoint in
`EDITOR_PARITY.md`. Full parity and remaining recognition errors stay queued.

Realme release **2029** freshly scanned song/sparse/uneven copies placed first
in the photo picker: **117/175/133 symbols**, **5/8/6 staves**. Song export has
**[3,3,3,3,3]**, **92 notes/10 rests**; all note/rest lengths and order are
preserved. Native output has **32** second-row pitch changes using the real
staff (frozen local replay has 31); first ledger note is C4. All other song
rows are identical. Both control MusicXML scores and PDF rasters are identical
to release 2028; all three PDFs are one page. Play/Stop verified on the
corrected second row; no subjective listening claim.
After restart, all three new projects export byte-identically. The older
`NVRowsSong2028` also matches its pre-install export exactly, including its
unresolved row. Collection **33 → 36**; retained app logs have no Flutter,
crash or save errors. Tested APK SHA-256:
`201f9be91652ba7535bbf071c2a026f3df6920abbd960367d97215bfd11a3b88`.
Original preferences and Home/collection state restored; temporary helpers
removed, requested recent test copies retained. Eleven exports are hashed in
`Download/NoteVisionQA2029/`; complete facts in
`/tmp/note-vision-trace-2029/qa-facts.json`.

**Beam-guided pitch heads (2026-11-07):** dark beams sometimes beat the actual
head in the end-band ink comparison, producing large pitch errors. Only
quarter detections already interpreted as beamed eighths/sixteenths receive a
beam-guided pitch box, after unchanged NMS. A beam touching just one end band
(with the existing stem-tip reach) selects the opposite end. Missing, middle,
unrelated or both-end beam evidence keeps the previous ink fallback. Explicit
flagged, half and whole classes keep their existing estimates. `DetectedSymbol`
copies metadata with `copyWith`; its separate pitch box round-trips through
detection JSON. `PitchCalculator` alone consumes it. Moving the shared symbol
box was rejected because it reassigned ledger notes and changed dot attachment.
Seven frozen-output replays preserve all symbols, order, rhythm, source bounds,
staves and barlines. Only pitch step/octave changes: **25 song, 10 dense, 7
paired, 1 sparse**; uneven, mixed and clef-only scores are identical. The
**43** head ends were visually checked; this does not establish exact pitch
accuracy within the fixed end bands. Seventeen regressions cover beam direction,
ambiguous/unrelated/missing beams, short stems, explicit classes, public decode
through pitch/JSON, and all 43 real-photo cases. Disabling beam guidance makes
eight tests fail. Full **1,136 tests passed**, analysis clean. Evidence:
`/tmp/note-vision-heads-2030/`. Detector weights/cutoffs and old saved scores
remain unchanged. Precise head fitting, missing/wrong symbols and full parity
remain queued.

Realme release **2030** fresh song/dense/paired scans: **117/225/153 symbols**,
**5/9/7 staves**, **25/9/7 pitch changes** (dense local replay has 10). All
exported non-pitch note fields, note/rest counts, row/bar assignments and
key/meter declarations are preserved: **92/10**, **172/8**, **139/0** notes/rests
and **15/27/21 bars**. All three PDFs are one page and visually checked.
Song second-row Play/Stop passed; subjective listening was not performed.
The re-encoded dataset dense copy gave 230 symbols and was rejected as a
baseline comparison before Save. Original dense/paired compressed JPEG data
and decoded pixels were preserved in QA copies; only their EXIF date text
changed to make them recent. Source originals and orientation are unchanged.
Hashes and pixel/scan checks: `phone/recent-pixel-copies.json` in the evidence
directory. Picker timestamp ties can reorder thumbnails; verify the preview.
After restart, all three new projects export byte-identically. The older
`NVTraceSong2029` matches its pre-install export exactly. Collection **36 →
39**; retained app logs show no Flutter/crash/save errors. Original font and
rotation preferences and Home/collection state restored; temporary helpers
removed, requested test copies retained. Eleven exports and two original-byte
input copies are archived/checksummed in `Download/NoteVisionQA2030/`.
Complete facts: `/tmp/note-vision-heads-2030/qa-facts.json`. Tested APK SHA-256:
`04a3c16005dda1af860ca2a827c841566351c0d88e405f3eb1c883f29e815cbb`.

**Bounded head centering (2026-11-07):** `NoteheadCenterFinder` refines only
one-ended beamed pitch boxes. Solid rectangular support filters thin strokes;
only one compact, fully bounded component with supported middle and no enclosed
paper pockets supplies its vertical centre. Hollow, clipped, competing, weak,
out-of-frame and ambiguous-beam evidence keeps the previous estimate. Local
paper contrast is normalized for binary/8-bit inputs. Original symbol boxes,
NMS, ownership, rhythm, source bounds, model weights and cutoffs are unchanged.
Seven frozen-output replays change **11 pitch centres**, with two score changes
(song row 3/bar 2 and dense row 9/bar 3, **A4 → B4**). Every other score field
is identical; the other five complete scores are identical to release 2030.
Twenty-one tests cover fitting at two scales/stem directions, stroke/noise and
ambiguity fallbacks, binary/8-bit contrast, decoder → pitch/JSON, three photo
centre intervals and three deliberately unresolved photo controls. Disabling
fitting fails ten tests. Full **1,157 tests passed**, analysis clean.
The production Dart annotation-box diagnostic (`tool/notehead_center_eval_test.dart`)
covers **11,864** beamed filled heads on unshared stems, with labelled boxes
and end selection:
**1,700** fitted; normalized mean centre error **0.1831 → 0.1590** overall,
**0.2193 → 0.0513** on fits. Of fits, **1,436 improve, 252 worsen, 12 tie**;
**seven** worsen by over a quarter head height (thick crossing/slanted ink).
This is a centering proxy on known data, without model inference, not unseen
scan/pitch accuracy. Remaining uncertain heads and other symbol errors still
need review. Evidence: `/tmp/note-vision-centers-2031/`. Full parity stays queued.

Realme release **2031**: fresh song/dense/paired scans detect **117/225/153
symbols**, **5/9/7 staves**. The same **A4 → B4** occurs once in song and dense;
paired MusicXML is byte-identical and its PDF raster pixel-identical to release
2030. All other exported note fields, counts/order, key/meter and bar placements
are preserved (**92/10/15**, **172/8/27**, **139/0/21** notes/rests/bars).
All PDFs are one page; new song/dense renders visually checked. Play/Stop
passed; no subjective listening claim. Recent copies preserve compressed image
pixels/orientation and originals; only copy dates change, staggered to avoid ties.
All three saved results cold-reopen with byte-identical exports. The older
`NVHeadsSong2030` matches its pre-install export exactly. Collection **39 →
42**; **50** retained app log lines have no Flutter/crash/save errors. Original
font/rotation and Home/collection state restored; temporary helpers removed,
requested recent copies retained. Eleven exports archived/hashed in
`Download/NoteVisionQA2031/`; complete facts in the evidence directory.
Tested APK SHA-256:
`2c3d46979cd372ace2b1dda3525e257d98cfa54bfdb9e895619a54a1f6f55f1f`.

**Key-signature diagnosis (2026-11-08):** the dense photo visibly repeats
three sharps on nine rows (27 glyphs). Both historical detections and a replay
of frozen local raw outputs retain leading counts **1,2,2,3,2,1,3,3,3**;
the mapper returns exactly those counts. Six missing sharp candidates peak at
**0.171/0.228/0.355/0.283/0.294/0.394**, below the frozen **0.40** cutoff.
The seventh is confidently misclassified as `timeSig4` (**0.668**, sharp
score at most **0.013**). No missing glyph has a qualifying raw sharp candidate
lost in suppression/staff assignment/signature grouping under the diagnostic's
local matching rules. Supplying the 27 labelled glyphs yields three sharps on
every row while preserving every mapped note/rest. This supports model-side
recognition work for this page, not a general claim that all signature mapping
is correct. No production/model/cutoff changes or new phone build.
`tool/key_signature_trace_test.dart` and `key_sharp_centers.json` reproduce the
trace/counterfactual; optional `NV_KEY_WORK`, `NV_KEY_REPORT`, `NV_KEY_LABELS`
enable raw-output and annotation audits. The final B9 24-class **test** labels
already contain all 27 key sharps (29 total including body accidentals).
Keep this known test page in its split; investigate separate validation pages
before choosing threshold calibration or more training examples. Original
dataset files are unchanged. Evidence: `/tmp/note-vision-key-triage-2031/`.
Frozen-fixture and raw-output/annotation diagnostics pass; final analysis is
clean and all **1,157 tests pass**. Initial verification hit the `/tmp` quota;
reruns using the ignored project build cache completed successfully.

**Selected-row key corrections (2026-11-08):** Review → Clef, key and time
signature → Correct key across rows opens an explicit row/key selection and
Current/Proposed preview beside the original photo. Only the current row is
selected initially; Select all is an explicit choice. The correction changes
opening keys and repeated inherited values through the first different key,
preserving later key changes, written notes/accidentals, rhythm and scan evidence.
Rows already matching are skipped. One correction uses the existing review
history, Undo/Redo, save and conflict-checked restore path. Stale previews and
playback locks cannot apply an edit. Available only for independent sequential
scan rows; ensembles/imported sources, linked/TAB/percussion staves are excluded.
Implementation: `scan_key_correction.dart`, `scan_key_correction_sheet.dart`.
Thirteen new domain/widget tests include real dense-photo correction,
history/JSON/Undo/Redo, playback/XML naturals and responsive layouts. Final
analysis clean; all **1,170 tests passed**. Evidence:
`/tmp/note-vision-key-rows-2032/`.
Full MuseScore parity remains queued.

This corrects opening sections only. A later key context may itself be a scan
error and remains for separate bar review; this does not establish that the
whole transcription is correct. The native dense scan retains its existing
later -1 contexts on row 1/bar 3 and row 2/bars 2–3. Distinguishing a note's
accidental at a bar opening from an actual key change is a separate app-side
investigation, independent of the model's missed opening sharps.

Realme release **2032** passed QA using saved `NVCenterDense2031`: installation
preserved its fresh baseline byte-for-byte. Default single-row selection,
Cancel, Current/Proposed and row/photo following passed. Single-row correction
changes two key entries; batch selection changes **12 entries across five rows**,
skipping four matching rows and preserving later different keys. Every written
field of **172 notes / 8 rests** is preserved; **14 sounding alterations** follow
the corrected key (including explicit natural/carry behavior). One Undo restores
the baseline; one Redo reproduces the batch export. Corrected cold reopen is
byte-identical. Saved History restores the original, and a second cold reopen
matches the pre-install baseline exactly. PDF is one page and visually checked;
Play/Stop, 1.8x text and landscape checked. All **42 projects** remain, original
font/rotation and Home restored, temporary device helpers removed. Eleven
exports archived/checksummed in `Download/NoteVisionQA2032/`; **386 retained app
log lines**, no Flutter/crash/save errors. Facts:
`/tmp/note-vision-key-rows-2032/phone/qa-facts.json`. Tested APK SHA-256:
`d383b684c0e09c203b0e3fd2d8dfaebf96aea4a8fa891ce1029763bd8063617d`.
No model change, fresh inference, iOS test or subjective listening claim.

**Phone QA photos:** user authorized dataset reads from
`/home/ken/Workspace/note-vision-data`. `tool/android_qa_images.py --serial
6d718c9c --batch <new-batch> <photo> ...` creates checksum-verified copies in
`Pictures/NoteVisionQA`, refreshes only their file dates, and synchronously indexes
them so pending adb writes become visible. The first supplied photo sorts newest.
Selected dataset photos have no embedded EXIF capture date; the helper
stops if an older embedded date could override recency. It refuses to replace an
existing different copy; use a new batch for a different selection. Originals remain unchanged. Keep this album for future
QA; verify the picker visually after refreshing rather than assuming copy time
controls its order.

**Guided bar review (2026-11-05):** Review groups questions by original row/bar,
opens the source photo automatically (crop/full-page and linked symbol outline),
and embeds a tappable bar with pitch/illustrated length controls and row-scoped
clef/key/meter choices. Scanned bars get explicit setup questions even when the
model is confident; suggestions wait for setup confirmation in every affected
bar. No meter/clef is borrowed from another scanned exercise or inferred from
beat totals. Direct scan length corrections may temporarily exceed a suspect
meter, while timeline validation and the regular editor's default guards remain.
“Not sure · Review later” preserves unresolved questions separately from “Keep
original”; Save & close saves decisions with the score. Reopening starts with
pending bars; saved-for-later bars can be resumed. Music edits invalidate stale
decisions. Batch/History live under More; single-bar listening, previews, Undo
and conflict-checked History restore remain available. Closing checks never
claims the transcription is correct. **1,064 tests passed**, analysis clean;
release **2023** passed Realme QA below. Detector/model thresholds and
automatic reconstruction are
unchanged. Full parity (including scan chords/grand staves) remains queued.

**Fresh-sheet scanning QA (2026-11-05, release 2022):** three other existing
handwritten photos were freshly scanned on the Realme through Upload and the
full on-device pipeline; no suggested fixes accepted. All six/seven/nine
visible staves were found, and each editor/PDF result has one page. Saved
`NVFreshMixed2022`, `NVFreshPaired2022`, `NVFreshDense2022`; cold collection
retains all 12 prior projects (15 total). Recognition remains inaccurate:
initial 3/4 became 2/4 on the mixed sheet; the paired sheet's first bass bar
has one exported note instead of five; the dense sheet's three-sharp key varies
between rows and stacked notes lack chord grouping. The bar-assignment
follow-up is recorded above; next accuracy work should reproduce meter/key
errors before tuning the detector;
scan chord/grand-staff reconstruction remains on the parity roadmap. Evidence:
`/tmp/note-vision-fresh-scans-2022/report.json` plus original photos, scan
screenshots and raw MusicXML/PDF exports. Phone exports:
`Download/NoteVisionFreshScans2022/`. These are fresh runs of existing test
photos, not an unseen-photo accuracy benchmark. No app/model changes.

**Scanned row layout (2026-11-05):** sequential scan rows now have a display
projection in reading order. NVScan2020's eight rows × three bars fit on one
page in the editor, thumbnails and PDF instead of three ensemble columns.
Stored parts/notes and MusicXML stay intact; this does not merge exercises or
infer instruments. Ensembles/grand staves keep their existing layout. Touch,
drag, selection, review and playback coordinates map to original parts/bars;
Next/Previous symbol cross scanned-row boundaries. Missing row meter/key
context stays absent, and short-row alignment gaps are neither drawn nor
editable. Review previews use their own layout. Focused regressions: 14 passed;
full suite: **1,045 passed**, analysis clean. Release **2022** passed Realme
QA below. See EDITOR_PARITY.md.

**Manual scan reference (2026-11-05):** Edit manually retains a source-photo
reference alongside the editable paper; More → Original scan opens it without
a checker finding. It follows selection, supports full-page/crop view and
zoom, and closes independently. Missing evidence shows an explicit message.
Viewing is not a musical edit; pitch edits/undo preserve the photo and its
coordinates. Phone, small-phone, enlarged-text, landscape and tablet captures
checked; **1,031 tests passed**, analysis clean. Historical real-photo triage
and its measurement limits are recorded in `EDITOR_PARITY.md`. Recognition
weights/thresholds are unchanged; this improves correction workflow, not
detector accuracy. Release **2021** passed Realme QA: reference retained during
touch correction and undo/redo, source tracking, full-page/crop, large text,
landscape and cold reopen. Edited export was byte-identical after restart;
the original score was restored and verified byte-identical afterward.

**Scan reliability completed (2026-11-05):** cancelled, reset or superseded
scans cannot publish stale results/errors. Retries clear previous output and
serialize native detection; leaving during loading/detection releases the
model after that operation finishes. Eight new regression cases reproduced
the failures before the fix; **1,022 tests passed**, analysis clean. Release
**2020** passed Realme early-exit/rescan, original-image comparison, save,
MusicXML export, playback smoke check and cold reopen. Detector weights,
thresholds and reconstruction remain unchanged; no accuracy gain claimed.
Next: use real-photo pitch/rhythm errors and correction friction to choose
the next improvement. Full parity remains in the backlog. Details/evidence:
`EDITOR_PARITY.md`, "Scan lifecycle reliability".

**Device QA completed (2026-11-04):** the note-input fixes, Chord/Insert
controls and TAB display changes passed on the Realme in release **2017**
from `c738255`. The user's test-before-next-feature requirement for that
revision is satisfied.
Automated checks also passed (990 tests, analysis clean). Results and local
evidence are recorded in Stage 3A of `EDITOR_PARITY.md`.

**Classical orchestra completed (2026-11-05):** template and two-staff
horn support implemented; analysis clean, **998 tests passed**. Release
**2018** passed physical QA on the Realme (creation, independent horn notes,
undo/redo, written/concert pitch, mixer, playback, MusicXML/PDF export,
re-import, cold restart and save/reopen). Stage 5C records the evidence.
The test-before-next-feature checkpoint for that revision is satisfied.

**Symphony orchestra completed (2026-11-05):** 25 instruments / 26 staves,
with harp grand staff and one-line orchestral percussion maps; **1,014 tests
passed**, analysis clean. All sounds fit 11 pitched channels plus percussion
channel 10. Large-ensemble PDF headers reserve physical title/composer space.
Release **2019** passed physical editing, shared percussion mixing, PDF export
and cold save/reopen checks on the Realme. Stage 5C records the evidence;
subjective listening remains deferred. Marching templates and family-bracket
engraving remain.

Editor expansion toward MuseScore Studio capabilities and UI/UX is tracked in
[`EDITOR_PARITY.md`](EDITOR_PARITY.md). Branch: `feat/musescore-editor`. Stage 1
adds shared commands, searchable actions, octave/duration shortcuts and safe
note/rest conversion. The user cancelled the quota-reset automation request.
Stage 2A retains imported MusicXML and exact source timing in optional
`Score.musicXmlSource`. Imported source events are not a live edited timeline.
Preserving export patches supported pitch/beam/metadata edits; complex rhythm or
structure changes fail explicitly instead of losing notation. See the checkpoint
for remaining engine work and verification. Stage 2B adds a live rational
voice/staff timeline, lane-aware capacity checks, independent MIDI note-offs
and shared-bar playback for imported ensembles. Scanned projects keep sequential
staff reading order. Complex source structure changes and sparse timewise bars
fail playback explicitly. Release build 2002 was tested on Android 11, including
import, playback, editing/undo and project save/reopen. Engraving and full
MuseScore parity remain incomplete. Decision: MuseScore's code is not
ported or translated (GPLv3); its features and UI are studied and
reimplemented. Every feature is checked against MuseScore Studio 4.7.5 by
`test/musescore_parity/` (see `EDITOR_PARITY.md`, "MuseScore comparison
tests").

Latest physical check: release **2023**, Realme RMX1851 / Android 11,
2026-11-05. Guided Review automatically shows the original photo beside the
current bar. Checked crop/full page, C5 → D5 → Undo, eighth → half → Undo,
key-signature choices/Undo, and 2/4 → 3/4 → History restore. Deferred the first
bar of NVFreshMixed2022; Save & close and cold restart retained 18 pending bars
and one saved for later, starting at Row 1 / Bar 2. All 15 projects retained.
The mixed score's restored/cold MusicXML matches its baseline byte-for-byte.
User edits in NVFreshDense2022 were saved/exported before installation and its
post-update export is also byte-identical. Single-bar listening, 1.8x text
and landscape checked; Android's active 44.1 kHz stereo track had zero track
underruns. No app Flutter/crash/save errors in inspected logs. Original font
and rotation preferences restored; helper removed. Mixed guided review left
open at Row 1 / Bar 2 with playback stopped. Evidence:
`/tmp/note-vision-phone-2023/` (`qa-facts.json`); phone exports:
`Download/NoteVisionQA2023/`. No iOS or new subjective listening test.

Previous physical check: release **2022**, Realme RMX1851 / Android 11,
2026-11-05. NVScan2020 now shows eight rows of three adjacent bars on one
editor page; its PDF also has one page. Touching row two selected its original
E3; Focus selected bar, Up to F3 and Undo worked. Original scan tracked that
row's selected note. Latest user edits were saved before the app update;
exports after install, QA Undo and cold reopen match that latest baseline
byte-for-byte. All 12 projects retained; NVSymphony2019 retains its stacked
ensemble layout. Playback from row two stayed on page 1/1; Android showed an
active 44.1 kHz stereo track with zero track underruns. Enlarged text (1.8x)
and landscape checked. App logs had no Flutter/crash/save errors. Phone font
and rotation preferences restored; helper removed, NVScan2020 left open with
playback stopped. Evidence: `/tmp/note-vision-phone-2022/` (including
`qa-facts.json`); phone exports: `Download/NoteVisionQA2022/`.
MusicXML retains original parts. No iOS or new subjective listening test.

Previous physical check: release **2021**, Realme RMX1851 / Android 11,
2026-11-05. More → Original scan and Review → Edit manually both retain an
editable score beside its photo. Touch Up changed G2 to A2; undo/redo and
the selected-symbol outline worked, with source tracking into Bar 2.
Full-page/crop, 1.8x text and landscape checked. Saved A2 cold-reopened with
a byte-identical export and its photo intact. Restored G2, saved and verified
the export against the baseline byte-for-byte. All 12 projects retained;
NVScan2020 left open with reference visible and playback stopped. Original
font/rotation settings restored and helper removed. Evidence:
`/tmp/note-vision-phone-2021/`; phone exports: `Download/NoteVisionQA2021/`.
No iOS or new subjective listening test.

Phone automation: lock rotation during coordinate-based checks and restore
preferences afterward. Verify native DocumentsUI's SAVE action and filename
EditText before typing; the guarded `/tmp/note-vision-phone-2022/export.py`
uses current UI labels/bounds, preventing filename input into the editor.

Previous physical check: release **2020**, Realme RMX1851 / Android 11,
2026-11-05. Starting a scan then immediately returning to Capture did not
initialize the detector. A fresh scan of the same handwritten test photo
completed with eight traced staves and 240 detected symbols. Original scan
comparison worked. Saved **NVScan2020** (eight parts, 171 notes, eight rests);
its cold-reopen MusicXML export was byte-identical. All 11 prior projects
retained (12 total). Short playback smoke check showed an active 44.1 kHz
stereo track with zero underruns; subjective listening remains deferred.
Display settings remain 0.9 font scale / automatic rotation; helper removed,
NVScan2020 left open with playback stopped. Evidence:
`/tmp/note-vision-phone-2020/`; phone files: `Download/NoteVisionQA2020/`.
No iOS test.

Previous physical check: release **2019**, Realme RMX1851 / Android 11,
2026-11-05. Saved **NVSymphony2019** and **NVRename2019**; all nine previous
projects retained (11 total). Checked mapped snare/side-stick, bass drum and
cymbal entry, independent harp staves, shared percussion kit/volume/pan,
per-part mute, undo/redo and rename/reorder before Apply. Both saved projects
cold-reopened with byte-identical MusicXML exports. The 26-staff PDF has a
clear title/composer header. A full-ensemble fixture played and retained all
26 notes unchanged through import/export. Enlarged text (1.8x) and landscape
checked; original display settings restored and keyboard helper removed.
Android's active 44.1 kHz stereo track had zero underruns; subjective listening
remains deferred. Evidence: `/tmp/note-vision-phone-2019/`; phone exports:
`Download/NoteVisionQA2019/`. No iOS test.

Previous physical check: release **2018**, Realme RMX1851 / Android 11,
2026-11-05. Saved **NVClassical2018**; all eight earlier projects retained
(nine total). Horns have different whole notes (written G4/B4, sounding C4/E4),
one mixer strip and the French horn sound. Cold-reopen export is byte-identical;
import/export is XML-equivalent. PDF bracket and notes visually checked;
1.8x text and landscape checked, original display settings restored.
Android's active 44.1 kHz stereo track had zero underruns; subjective listening
check deferred because the user could not listen. Evidence: `/tmp/note-vision-phone-2018/`,
phone exports: `Download/NoteVisionQA2018/`. Source-preservation import warning
and complex-source editing limits still apply. No iOS test.

Previous physical check: release **2017** (`c738255`), Realme RMX1851 / Android
11, 2026-11-04. Exact 32nd gaps/residual rests, split tied accidentals across
key changes, three-piece tie playback, touch chord pitches above/below,
duplicate suppression, Insert and injected Ctrl+Shift+G, undo/redo, MusicXML
exports, TAB editor/PDF hiding, landscape and 1.8x text checked. Saved
**NV32Gap2017** reopened after a cold restart with identical exported notes
and ties; **NVChord2017** also saved. Six original projects retained (eight
total); playback stopped with NV32Gap2017 open. User confirmed clear audio;
the app's active 44.1 kHz stereo speaker track had zero underruns at both
captures. Original display preferences restored; no iOS test. Stage 3A of
`EDITOR_PARITY.md` records evidence; the earlier mixer check remains in 5A.

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
| Grand staff | ❌ Not detected in scans (import, editing and export support it) |
| Chords | ❌ Not detected — the model reads two heads on one stem as one note |
| Ties, slurs, tuplets | ❌ Not detected in scans (import, editing, playback and export ✅) |

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
- Grand staff ✅ in import, editor, PDF and export (`Part.staff` links a lower staff); scans still read each staff separately
- Chords: the model has no class for a second notehead on a stem, so a scanned chord becomes one note
- Dotted note/rest rhythms ✅ reconstructed from scan
- Repeat barlines ✅ detected and exported to MusicXML
- Ties, slurs and tuplets ✅ (import, editor, PDF, playback, export)
- 32nd notes or smaller
- Grace notes ✅ before a note (appoggiatura, acciaccatura); grace notes after a note and grace chords are not supported (ornaments ✅: trill, mordents, turn)
- Tempo markings, staff/system text, rehearsal marks and common chord symbols ✅ (editor, playback where applicable, MusicXML and PDF); tempo ramps and richer text/chord styles remain
- Repeats, endings, D.C./D.S./coda ✅ (editor, playback, PDF, MusicXML); "play repeats" after a jump and play counts are not supported
- Multiple voices on one staff ✅ written (voices 1–4) and drawn in editor and PDF; moving notes between voices is not yet supported
- Lyrics ✅ (note entry, verses, hyphens/melismas, MusicXML, project save and PDF); no scan recognition or rich-text style editor
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

# Sprint 11 — Reconstruction Improvements

Tickets: BGC-105 through BGC-112
Focus: OMR accuracy, reconstruction quality, and editor polish from real-world usage.

---

## BGC-105 — Dotted Note/Rest Reconstruction

**Owner:** Canete
**Priority:** High
**Area:** Reconstruction pipeline

**Background:**
The YOLO model already detects `augmentationDot` as one of its 57 classes, but the reconstruction pipeline (`SemanticInferrer` / `ScoreBuilder`) never consumes these detections. Dotted rhythms appear in virtually every piece of printed music.

**What to do:**
In the reconstruction pipeline, after stem/flag/beam association, find `augmentationDot` detections that are spatially adjacent (to the right of) a notehead or rest. Apply a 1.5× duration multiplier to the matched symbol.

**Acceptance criteria:**
- A dotted quarter note is reconstructed with `type: "quarter"` and `duration: 3` (divisions × 1.5).
- A dotted half note → `type: "half"`, duration = 6.
- Dotted rests follow the same rule.
- Double-dotted notes (two adjacent dots) are out of scope.
- All existing tests pass.
- Unit tests added for the dot-matching logic covering: dot adjacent to notehead, dot adjacent to rest, no dot present, dot too far to match.

---

## BGC-106 — Chord Reconstruction

**Owner:** Canete
**Priority:** High
**Area:** Reconstruction pipeline

**Background:**
Multiple noteheads can share a single stem (chord). The model detects all noteheads individually, and `StemAssociator` currently assigns one notehead per stem. Chords are extremely common in piano and keyboard scores.

**What to do:**
1. **`Note` model** — add `final bool isChordTone` (default `false`), following the same pattern as the existing `beamed` field. A chord tone starts at the same rhythmic position as the preceding note in `symbols`. No new class needed.

2. **`StemAssociator`** — group multiple noteheads to one stem when their bounding boxes overlap horizontally with the stem and their Y positions are within a reasonable range. The first notehead becomes a normal `Note`; additional noteheads become `Note(isChordTone: true)`.

3. **MusicXML export** — emit `<chord/>` inside `<note>` when `isChordTone == true`.

4. **Playback** — `PlaybackConverter` should play all notes in a chord simultaneously (emit note-on for each chord tone without advancing the clock).

5. **Editor/Painter** — treat chord tones as non-selectable siblings of their primary note for now (selection of individual chord tones is out of scope).

**Acceptance criteria:**
- Two noteheads on one stem reconstruct as a chord (two notes at the same rhythmic position).
- Chord is preserved in MusicXML export with correct `<chord/>` tags.
- Single-notehead stems are unaffected.
- All existing tests pass.
- Unit tests added for: two-notehead stem → chord, three-notehead stem → chord, single notehead unchanged, noteheads too far apart do not group.

---

## BGC-107 — Repeat Barline Detection

**Owner:** Canete
**Priority:** Medium
**Area:** Reconstruction pipeline + MusicXML export

**Background:**
`repeatDot` is one of the 57 detected classes. A repeat barline consists of a thick barline plus two dots. These appear in virtually all sheet music but are currently ignored — barlines are reconstructed as plain barlines regardless.

**What to do:**
In `MeasureGrouper`, detect when a barline has one or more `repeatDot` detections nearby. Identify the barline type:
- Dots to the right of a barline → start repeat (`|:`)
- Dots to the left → end repeat (`:|`)
- Dots on both sides → end + start repeat

Add a `barlineType` field to `Measure` (or a separate `Barline` model) and encode it in MusicXML export as `<barline location="right"><bar-style>light-heavy</bar-style><repeat direction="backward"/></barline>`.

**Acceptance criteria:**
- A `:|` repeat sign is exported as a backward repeat barline in MusicXML.
- A `|:` repeat sign is exported as a forward repeat barline.
- Plain barlines are unaffected.
- Playback does not need to honour repeats (out of scope).
- All existing tests pass.
- Unit tests added for: end repeat detection, start repeat detection, end+start repeat, plain barline unchanged.

---

## BGC-108 — Double Whole Note Support

**Owner:** Canete
**Priority:** Low
**Area:** Reconstruction pipeline

**Background:**
`noteheadDoubleWhole` (breve) is detected by the model but the reconstruction pipeline likely treats it as an unknown or falls back to quarter. A double whole note equals 2 whole notes (16 divisions at the standard 2-divisions-per-quarter encoding).

**What to do:**
In `SemanticInferrer` / `ScoreBuilder`, handle `noteheadDoubleWhole` and assign `type: "breve"`, `duration: 16`. Verify the MusicXML export uses `<type>breve</type>`.

**Acceptance criteria:**
- A double whole notehead reconstructs with `type: "breve"` and correct duration.
- MusicXML export is valid (passes schema check).
- All existing tests pass.
- Unit test added for `noteheadDoubleWhole` → breve duration mapping.

---

## BGC-109 — Ledger Line Pitch Accuracy

**Owner:** Canete
**Priority:** Medium
**Area:** Reconstruction pipeline

**Background:**
`legerLine` detections are currently unused. Notes sitting on or between ledger lines (e.g., middle C below the treble staff, or high C above it) have their pitch calculated purely from Y position relative to the staff. Without ledger line anchoring, octave errors are common for extreme pitches.

**What to do:**
In `PitchCalculator`, incorporate nearby `legerLine` detections as additional Y reference points. Each ledger line extends the staff grid by one step. Use them to constrain/snap the pitch calculation for noteheads that fall outside the five staff lines.

**Acceptance criteria:**
- Middle C (one ledger line below treble staff) is consistently reconstructed as C4, not C3.
- Notes two ledger lines above the treble staff reconstruct in the correct octave.
- Notes within the staff are unaffected.
- All existing tests pass.
- Unit tests added for: middle C with ledger line → C4, high C with two ledger lines → correct octave, in-staff note unaffected by nearby ledger lines.

---

## BGC-110 — Per-Class Detection Confidence Thresholds

**Owner:** Canete
**Priority:** Low
**Area:** Detection pipeline

**Background:**
The detector uses a single global confidence threshold of 0.75 for all 57 classes (`TfliteSymbolDetector`). Structural symbols like `stem`, `beam`, and `staffLine` are reliably detected at high confidence; small symbols like `augmentationDot`, `accidentalNatural`, and `legerLine` are often suppressed by the global threshold because they score lower by nature of their size.

**What to do:**
Replace the single `_kConfidenceThreshold` constant with a `Map<MusicSymbol, double>` of per-class thresholds. Structural symbols keep 0.75; small/fine-grained symbols drop to 0.55–0.65. Tune values against the test image set.

**Acceptance criteria:**
- Augmentation dots, natural accidentals, and ledger lines are detected more consistently on test scans without a corresponding increase in false positives for notehead/stem classes.
- Threshold map is a named constant (easy to adjust).
- All existing tests pass.
- Unit test added for threshold lookup: each class returns the correct threshold value, unknown class falls back to the default.

---

## BGC-111 — Editor Header: Collapse Action Buttons into Overflow Menu

**Owner:** Boleche
**Priority:** Medium
**Area:** Editor UI

**Background:**
The `_EditorHeader` bar currently places Undo, Redo, Save, Export, and Scan Page as individual buttons in a single `Row` alongside the score title. On narrow screens (360 dp and below) the title column is squeezed to near-zero width, making the project name unreadable.

**What to do:**
Consolidate the secondary actions (Export, Scan Page) into a single `PopupMenuButton` overflow menu (`Icons.more_vert`). Keep Undo, Redo, and Save as primary inline buttons since they are the most frequently used. The title area should have a guaranteed minimum width of ~120 dp.

Layout after change:
```
[Back] [Title (expanded, min 120dp)] [Undo] [Redo] [Save] [⋮ More]
```

`⋮ More` menu items:
- Scan New Page
- Export MusicXML…
- Export PDF…

**Acceptance criteria:**
- On a 360 dp wide screen, the score title is fully visible (no ellipsis truncation on typical project names).
- All existing actions (export, scan) remain accessible via the overflow menu.
- Undo, Redo, Save remain as direct buttons.
- Disabled states (playback active, score empty) still apply to menu items.
- All existing tests pass.
- Widget test added for `_EditorHeader`: overflow menu contains Scan New Page, Export MusicXML, and Export PDF items; Undo/Redo/Save remain inline.

---

## BGC-112 — Score Genre/Label Classification

**Owner:** Canete
**Priority:** Medium
**Area:** Core services + Collection UI

**Background:**
After reconstruction the app knows the time signature, key signature, number of parts, note types, and pitch range of a score. This is enough to classify the piece into one of six labels using a simple priority-ordered rule engine — no ML or network needed.

**Label taxonomy (evaluated in priority order, first match wins):**

| Priority | Label | Type | Rule |
|----------|-------|------|------|
| 1 | Simple Melody | Basic | Single part · no/minimal key signature (≤1 sharp/flat) · ≥75% whole/half/quarter notes · pitch range ≤ 8 semitones |
| 2 | Children's Song | Basic | Single part · 2/4 time · no/minimal key signature (≤1 sharp/flat) · avg ≤ 4 notes per measure |
| 3 | Waltz | Genre | Time signature = 3/4 |
| 4 | March | Genre | Time signature = 2/4 |
| 5 | Classical | Genre | Specific rule only — NOT a fallback. Triggered by: ≥2 parts OR key signature ≥3 sharps/flats OR presence of 16th notes/beams throughout |
| 6 | General Piece | Fallback | None of the above matched |

Priority order matters: a 2/4 single-part simple piece labels as Children's Song (priority 2) before March (priority 4) is checked. Classical (priority 5) fires only when its specific rules are met — it is never used as a catch-all.

**What to build:**

1. **`ScoreClassifier`** — new pure-Dart class in `lib/core/services/score_classifier.dart`. Takes a `Score`, evaluates rules in priority order, returns a `ScoreLabel` enum. No storage — computed on demand.

```dart
enum ScoreLabel { simpleMelody, childrensSong, waltz, march, classical, generalPiece }

class ScoreClassifier {
  static ScoreLabel classify(Score score) { ... }
}
```

2. **Display in CollectionScreen** — show the label as a small pill/badge on each project card (same accent colour family, muted).

3. **Display in EditorShellScreen** — show the label as a secondary subtitle line in `_EditorHeader` below "Score Editor", replacing or joining the existing subtitle.

**Rule implementation notes:**
- Key signature: use `measure.keySignature?.fifths` from the first measure of the first part. `abs(fifths) <= 1` = simple key.
- Time signature: use `measure.timeSignature?.beats` and `beatType` from the first measure.
- Pitch range: scan all `Note` steps + octaves in the score, compute min/max in semitones.
- Note type ratio: count symbols by type; `whole/half/quarter` ÷ total notes.
- Part count: `score.parts.length`.
- 16th notes: any `Note` with `type == "sixteenth"` present.

**Acceptance criteria:**
- A single-part C-major piece with quarter notes → Simple Melody.
- A single-part 2/4 C-major piece → Children's Song (not March).
- A 3/4 piece → Waltz regardless of key or part count.
- A two-part piece with 4 sharps → Classical.
- A 4/4 single-part piece with mixed rhythms and no strong rule match → General Piece.
- Label badge visible on collection cards and in the editor header.
- `ScoreClassifier` is pure Dart and unit-testable with no Flutter dependencies.
- All existing tests pass.
- Unit tests added for each label: one test per label confirming the correct rule triggers, plus a test confirming priority order (e.g., 2/4 simple piece → Children's Song, not March).

---

## Summary

| # | Ticket | Owner | Priority | Status |
|---|--------|-------|----------|--------|
| 105 | Dotted Note/Rest Reconstruction | Canete | High | ✅ Done |
| 106 | Chord Reconstruction | Canete | High | ✅ Done |
| 107 | Repeat Barline Detection | Canete | Medium | ✅ Done |
| 108 | Double Whole Note Support | Canete | Low | ✅ Done |
| 109 | Ledger Line Pitch Accuracy | Canete | Medium | ✅ Done |
| 110 | Per-Class Detection Confidence Thresholds | Canete | Low | ⏳ Not started |
| 111 | Editor Header: Collapse Action Buttons into Overflow Menu | Boleche | Medium | ⏳ Not started |
| 112 | Score Genre/Label Classification | Canete | Medium | ⏳ Not started |

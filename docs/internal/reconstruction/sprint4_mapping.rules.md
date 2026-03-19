# Sprint 4 Reconstruction Rules

This internal spec defines what the detection-to-score mapper **will** and **will not** support in Sprint 4.  
It is the agreed source of truth for tester expectations, mock data, and mapping-side implementation decisions.

## Scope summary

Sprint 4 supports a narrow happy path:

- single staff only
- treble clef only (`clefG`)
- simple left-to-right symbol streams
- quarter, half, whole, and eighth notes
- quarter, half, and whole rests
- simple measures grouped by barlines
- no chords, ties, tuplets, key signatures, or accidentals yet

## Reconstruction output

The mapper outputs a minimal `ScoreModel` result.

Expected Sprint 4 output structure:

- one `Score`
- one `Part`
- one or more `Measure`s
- `Note` and `Rest` symbols emitted in left-to-right order within each measure
- mapper warnings/errors for unsupported or ambiguous cases

Default output values for Sprint 4:

- `title = ''`
- `composer = ''`
- `part.name = 'Detected Part'`
- `staff = 1` when a staff value is needed
- `voice = null` unless explicitly assigned by implementation

## Supported note types

The mapper supports these note constructions:

- whole note: `noteheadWhole` without stem or flag
- half note: `noteheadHalf` with an associated stem
- quarter note: `noteheadBlack` with an associated stem and no flag
- eighth note: `noteheadBlack` with an associated stem and one eighth-note flag

Supported flag symbols for eighth notes:

- `flag8thUp`
- `flag8thDown`

## Supported rest types

The mapper supports these rest symbols:

- `restQuarter`
- `restHalf`
- `restWhole`

## Supported clefs

Sprint 4 supports only:

- treble clef / G clef: `clefG` or `gClef`

If no supported treble clef is detected near the left side of the staff, the mapper must emit a warning and treat pitch reconstruction as ambiguous or unsupported for the affected notes.

## Supported structural symbols

Sprint 4 supports only simple measure-separating barlines:

- `barlineSingle`

Barlines are used only as structural separators for measure grouping.

Sprint 4 does **not** support:

- repeat barlines
- double barlines
- final barlines
- endings
- navigation markings

## Stem-notehead association

Stem ownership is inferred geometrically.

Rules:

1. A stem can attach to at most one notehead.
2. A notehead can attach to at most one stem.
3. A stem is considered a candidate for a notehead when:
   - the stem x-position overlaps the notehead x-range or lies immediately beside it, and
   - the stem y-range overlaps the notehead vertical center region.
4. If multiple stems are candidates, choose the closest stem by horizontal distance to the notehead center.
5. If no stem matches, the notehead is only reconstructable as a whole note candidate.

Practical outcome:

- `noteheadWhole` does not require a stem
- `noteheadHalf` and `noteheadBlack` normally require a stem for reconstruction in Sprint 4

## Flag-stem association

Flag ownership is also inferred geometrically.

Rules:

1. A flag can attach to at most one stem.
2. A stem can own at most one Sprint 4-supported flag.
3. A flag is considered a candidate for a stem when it is positioned close to the stem endpoint and matches the expected side/orientation for that stem.
4. If multiple flags are candidates for one stem, choose the nearest candidate and emit a warning if the choice is ambiguous.
5. Only one eighth-note flag is supported in Sprint 4.

Practical outcome:

- `noteheadBlack` + stem + one `flag8thUp` or `flag8thDown` reconstructs as an eighth note
- anything beyond one flag is unsupported in Sprint 4

## Staff ownership inference

Every symbol is assigned to the single detected staff whose vertical span is the best match.

Rules:

1. Prefer the staff whose `topY..bottomY` range contains the symbol center y-position.
2. If the center is outside the range, choose the nearest staff by vertical distance to the staff midpoint.
3. If more than one staff is present, the input is unsupported in Sprint 4 and the mapper must emit a warning instead of attempting multi-staff reconstruction.

## Measure grouping from barlines

Measures are inferred from barlines in reading order.

Rules:

1. Sort staff-owned symbols by x-position.
2. Sort barlines by x-position.
3. Symbols between the left edge of the staff and the first barline belong to measure 1.
4. Symbols between consecutive barlines belong to the next measure.
5. Symbols after the last barline belong to the final measure.
6. Barlines are treated as measure separators, not musical symbols to emit.

If no barlines are present, the mapper may reconstruct the symbol stream as a single measure and emit a warning if measure boundaries are uncertain.

Sprint 4 assumes clean, non-overlapping barlines and simple measure ordering.

## Symbol ordering

Within a measure, reconstructed notes and rests are emitted in ascending x-position order.

Rests follow the same ordering rule as notes.

## Pitch calculation from note position plus clef

Pitch is derived from vertical position on the staff after staff ownership is known.

Rules:

1. Use the notehead vertical center as the pitch anchor.
2. Map the anchor to the nearest staff line or space using the detected `lineYs` for the assigned staff.
3. For treble clef, use standard bottom-line E4 reference and count diatonic steps by staff line/space movement.
4. Ledger-line handling is out of scope for Sprint 4 unless the position is only one simple step beyond the staff and still unambiguous.
5. Accidentals are ignored in Sprint 4, so pitches are natural-note only.

Treble clef staff reference from bottom to top:

- line 1: E4
- space 1: F4
- line 2: G4
- space 2: A4
- line 3: B4
- space 3: C5
- line 4: D5
- space 4: E5
- line 5: F5

## Duration inference from notehead + stem + flag

Duration is determined by notehead fill plus attached stem/flag information.

Rules:

- `noteheadWhole` => whole duration
- `noteheadHalf` + stem => half duration
- `noteheadBlack` + stem + no flag => quarter duration
- `noteheadBlack` + stem + one `flag8thUp` or `flag8thDown` => eighth duration
- `restWhole` => whole rest duration
- `restHalf` => half rest duration
- `restQuarter` => quarter rest duration

Anything beyond one flag or beyond these notehead/rest combinations is unsupported in Sprint 4.

## Time signature handling

Sprint 4 does not infer time signatures from detections.

Measures are grouped only by barlines and symbol ordering.  
No duration-total validation against a detected or inferred time signature is performed in Sprint 4.

## Unsupported symbol behavior

Unsupported symbols must not crash the mapper.

Expected behavior:

- ignore the unsupported symbol for score reconstruction
- record a warning explaining that the symbol is unsupported in Sprint 4
- continue reconstruction unless the unsupported symbol creates ambiguity in staff ownership or measure grouping

## Empty or partial input behavior

The mapper must fail safely on empty or partial input.

Expected behavior:

- if no staff is detected, return an empty or partial result with a warning
- if no supported symbols are detected, return an empty or partial result with a warning
- if only some symbols are reconstructable, reconstruct only the supported and unambiguous subset
- never crash on empty input

## Geometric tolerances

Exact proximity thresholds for stem-notehead association, flag-stem association, and related geometric ownership checks are implementation-defined in Sprint 4.

These thresholds must:

- be implemented as consistent code constants or rules
- be applied consistently across mock tests and runtime mapping
- not change silently without updating related tests

## Ambiguity handling

When the mapper cannot make a single confident interpretation, it should fail safely instead of inventing notation.

Expected Sprint 4 behavior:

- skip the ambiguous symbol or measure candidate
- record a mapper warning/error explaining why reconstruction was not possible
- continue only when doing so does not corrupt surrounding measure structure

Examples of ambiguity:

- notehead equally close to two stems
- note position between staff steps without a clear nearest line/space
- missing or conflicting treble clef
- conflicting barline order
- symbol not clearly owned by the single supported staff
- a flag ambiguously close to multiple stems

## Unsupported in Sprint 4

The mapper does **not** support these yet:

- multiple staffs or grand staff
- bass clef, alto clef, tenor clef, or clef changes
- chords
- ties or slurs
- beams
- sixteenth notes or smaller values
- dotted rhythms
- tuplets
- accidentals and key signatures
- time signature interpretation beyond preserving simple measure grouping assumptions
- grace notes
- repeats, endings, or navigation markings
- cross-staff notation
- complex ledger-line reading
- pickup/anacrusis-specific logic
- voices/layers within one staff

## Mock input assumptions

Sprint 4 mock detection fixtures should provide:

- normalized symbol coordinates
- clean staff line positions in reading order
- barlines that are sortable by x-position
- supported symbol names matching this document exactly

This helps ensure test failures reflect mapper logic rather than inconsistent mock data.

## Tester guidance

Use this document when building expected outputs for Sprint 4 mapping tests.

Recommended happy-path fixtures:

1. single-staff treble-clef melody with quarter notes only
2. whole, half, quarter, and eighth note mix on one staff
3. simple quarter/half/whole rests inside barline-delimited measures
4. ambiguous cases that should produce warnings or partial reconstruction instead of fabricated notes
5. no-barline case that reconstructs as a single measure with warning if needed
6. unsupported symbol case that is ignored with warning
7. empty-input case that returns safely without crash
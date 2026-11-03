# NoteVision notation editor

User-approved objective: MuseScore Studio-level editing capabilities **and UI/UX**
inside NoteVision, retaining offline mobile scanning and recognition. A handoff to
another app does not satisfy this objective. Work branch: `feat/musescore-editor`.

This is a multi-stage implementation. A completed stage is not full parity.
The user cancelled the automatic quota-reset trigger request. Do not install one.

## Reference and implementation policy

Use the [MuseScore Studio handbook](https://handbook.musescore.org/llms.txt) as the
feature inventory. Record the exact release before claiming compatibility.
Read source directly when needed; REA is unnecessary. No MuseScore code or assets
have been incorporated in the first stage. Any future reuse must first identify
the relevant licenses and distribution requirements.

Keep Flutter and the existing offline app operational while implementing complete
vertical slices: score representation, editing/history, rendering/hit testing,
persistence, MusicXML, PDF and playback where applicable. Avoid visible controls
for features that have no implementation. Unknown imported notation must not
silently disappear; preservation is a prerequisite for complex score editing.

## Capability inventory

| Area | Starting point | Work required |
| --- | --- | --- |
| Workspace | Adaptive dark dock, paper canvas, pan/zoom, guide | Searchable commands, richer properties/palettes, touch and keyboard parity, timeline/navigation |
| Note input | Tap/drag whole through 16th notes/rests | Step input, pitch keys, octave/duration shortcuts, chords, voices, MIDI, additional values |
| Selection/editing | One symbol or measure context, 50-step undo | Ranges, multiple selection, clipboard, repeat, transpose, filters and atomic batch edits |
| Rhythm | Basic values/dots, beams, exact live voice timing and source ratios | Editable tuplets/grace notes, measure rests, explicit pickups and ties |
| Pitch | Diatonic moves and accidentals; partial key/clef support | Octave moves, full key/clef editing, chromatic/enharmonic transpose, concert/transposed pitch |
| Expression | Limited symbol model | Slurs, articulations, dynamics/hairpins, ornaments, tremolo, lines/pedal and playback semantics |
| Text | Title/composer | Lyrics, chord symbols, tempo/rehearsal marks, staff/system text, fingering |
| Structure | Parts and bars, page breaks | Instrument/staff management, linked parts, staff groups, repeats/voltas/jumps |
| Engraving | Fixed-grid CustomPainter plus separate PDF renderer | Shared layout, collisions, proportional spacing, chord/voice engraving, styles and page/system controls |
| Playback | Simultaneous voices/imported parts, sequential scanned staves, transport/tempo | Mixer, loops, metronome, repeats, expression and MIDI/audio export |
| Interchange | MusicXML subset and local project JSON | Lossless preservation/migration, complex round-trip fixtures, additional exports |
| Specialized notation | Not implemented | Tablature, percussion, cross-staff, alternate staff types and instrument-specific notation |
| Platform integrations | Offline Android/iOS primary, desktop builds | Assess desktop plugins/sound engines separately; do not silently exclude them from the requested scope |

## Stages and acceptance

1. **Commands and editing workflow:** shared command availability/dispatch,
   searchable actions with reasons when disabled, keyboard/touch access,
   octave and rhythm edits, safe note/rest conversion, undo and interaction locks.
2. **Document/timeline foundation:** explicit voice/staff onset and rational
   duration, stable identities, unknown-notation preservation and versioned
   migration. Audit native engine reuse against a representative score before
   committing to a full engine rewrite.
3. **Selection and composition:** range selection, clipboard, step input,
   chords/voices, transpose and part/staff management.
4. **Notation and engraving:** implement inventory families in complete vertical
   slices with shared screen/PDF rules and round-trip fixtures.
5. **Playback and polish:** mixer/expression/repeats, layouts, accessibility,
   templates and specialized notation. Audit remaining inventory item by item.

For each slice, test behavior and undo plus persistence/import/export effects,
check narrow phones/landscape/tablets and large text, run static analysis, and
update the checkpoint. Full parity requires evidence for all inventory families
and an explicit list of any platform-dependent differences.

## Checkpoint — 2026-10-28

- Persistent goal recorded in this thread; its latest status is `usageLimited`.
  The user explicitly requested continuation and cancelled the custom reset
  trigger. No automatic reset supervisor is installed; do not assume automatic
  quota-reset continuation is configured.
- Branch created with the pre-existing dirty workspace carried over intact.
  Existing changes include the editor shell/dock/help/palette/review and tests;
  do not reset or overwrite them. Initial tracked patch backup is
  `/tmp/notevision-editor-preexisting.patch` (untracked files were not in it).
- Baseline: `flutter test --no-pub test/features/editor/domain
  test/features/editor/model
  test/features/editor/presentation/editor_workspace_test.dart` — **70 passed**.
- Stage 1 implemented: shared `EditorCommand` definitions and availability;
  command search from the navigation bar and Ctrl/Cmd+K; keyboard selection,
  filtering and disabled reasons; octave moves; 3–7 duration shortcuts (choose
  an input value while entering, edit the selection otherwise); dot shortcut;
  note/rest conversion preserving identity, scan evidence and rhythm. Conversion
  refuses chord members/bases and repairs surrounding explicit beam groups.
- Touch controls expose octave and conversion actions. Search adapts to narrow
  screens, large text and a landscape keyboard; the underlying workspace stays
  stable behind modal text entry. Actions recheck playback/review locks after
  dialog dismissal.
- Final verification: **196 passed** with
  `flutter test --no-pub --reporter expanded test/features/editor/domain
  test/features/editor/model test/features/editor/presentation
  test/core/models/beam_grouping_test.dart`; static analysis on the editor and
  new tests reported **no issues**; `git diff --check` clean.
- Captured and visually inspected command search for phones/large text and
  landscape under `/tmp/notevision-commands/`. This is widget-level validation;
  no new on-device Android/iOS build has been tested yet.
- Newly confirmed foundation gaps: MusicXML `_buildMeasure` iterates only
  `<note>` elements, ignoring `<backup>`, `<forward>` and directions; `_buildSymbol`
  rounds source durations to two divisions per quarter and ignores notations and
  tuplet ratios. `PlaybackConverter.buildEvents` deliberately plays one entire
  part before the next. Native project JSON stores no original MusicXML tree.

## Stage 2A — retained documents and exact source time

- `Score.musicXmlSource` is an optional, versioned, immutable document envelope.
  It retains the full decoded source XML, the supported-model baseline, stable
  note bindings and exact source events. Older project JSON without this field
  continues to load; unknown envelope versions fail explicitly.
- `MusicalTime` stores reduced rational quarter-note values. Intermediate
  arithmetic uses BigInt and rejects results outside exact JSON integer range.
  Decimal divisions, tuplets and mid-measure division changes retain exact time.
- `MusicXmlSourceReader` honors backups/forwards, chord onsets, grace notes,
  voices and staves in partwise and timewise documents. Source indices include
  unpitched/grace notes that the old editable projection omits.
- Import preserves the original document through save/reopen, review identity
  assignment and undo/redo. It reports when some notation is retained but cannot
  yet be displayed or played. The projection also now honors mid-measure
  division changes and the default right location of repeat barlines.
- MusicXML export returns the retained document for unchanged imported music.
  Supported pitch/accidental/beam and metadata changes patch a copy of the source
  rather than rebuilding it. Lyrics, dynamics, tuplets, instrument declarations,
  layout, other creators, rights and unknown elements remain intact. Output
  declarations match the UTF-8 bytes written by the exporter, even for sources
  originally decoded from UTF-16 or Latin-1.
- For complex sources, rhythm/structure changes and unsafe tied-note pitch
  changes fail export with a clear explanation; local project saving still
  retains both the edited projection and original notation. Simple fully
  represented scores keep their existing generated-export editing workflow.
- Important boundary: `musicXmlSource.events` describes the **original source**,
  not a live timeline after arbitrary edits. This stage does not add polyphonic
  rendering/playback, editable tuplets, lyrics or full notation support. Do not
  feed these source events into playback as if they included later rhythm edits.
- Verification: the full Flutter suite passed **695 tests** before the final
  repeat/title coverage addition; the final focused MusicXML/model/export-UI run
  passed **121 tests**. Static analysis across `lib` and the new tests reported
  **no issues**; `git diff --check` is clean. The fixtures cover actual project
  disk save/reopen, skipped-symbol bindings, partwise/timewise files, exact
  timing, microtones, ties, encoding, metadata and export-error behavior.
  Commands: `flutter test --no-pub --reporter expanded`; then
  `flutter test --no-pub --reporter expanded test/features/music_xml
  test/features/musicXML test/core/models/musical_time_test.dart
  test/features/editor/presentation/preserved_source_export_test.dart`.
  No on-device Android/iOS build was performed in this stage.

## Stage 2B — live voice timing and ensemble playback

- Stage 1 and 2A were committed as `80decb7` (`feat(editor): add commands and
  source retention`). This stage builds on that checkpoint.
- `ScoreTimelineBuilder` derives exact rational onsets and durations from the
  current score. Voice/staff lanes have separate cursors; chord tones share
  their base onset. Capacity checks use the edited lane rather than summing
  every voice. Duration/dot changes and insertion retain undo behavior.
- Stable source bindings overlay supported rhythm edits onto original exact
  timing: written-duration ratios adjust source durations and reflow the same
  lane while retaining gaps and other voices. Original source events remain
  immutable. Complex add/remove/reorder and voice/chord-structure changes fail
  playback explicitly rather than silently using stale timing. Complex rhythm
  export still has the stage 2A restrictions.
- Playback layout is optional in project JSON. Existing projects without a
  source envelope retain sequential scanned-staff reading order; retained
  MusicXML imports default to simultaneous parts. Explicit layout persists.
  Shared ensemble bars align to the longest part/meter, with short-opening
  pickup handling and inherited meter changes. Timewise sources with omitted
  part bars fail playback explicitly until global measure slots are modeled.
- Playback schedules independent note-on and note-off boundaries, so short
  voice notes can end while long notes continue. Exact absolute boundary
  rounding avoids accumulated tuplet drift. Pause/resume, seeking, review
  audition, editing while paused and stale-timer cancellation remain covered.
  Playback errors allow retry after correcting the score.
- Ensemble transport scrubs shared bars instead of counting every staff's
  bars. It falls back to another part if the selected part lacks the target
  bar. Scanned-score transport keeps its existing staff order.
- Limitations: the current painter/PDF still use the earlier engraving rules;
  triplet symbols can crowd together and tuplet brackets are not drawn.
  Unrepresented grace/unpitched source events retain time but do not sound.
  All parts still use one piano channel; overlapping unisons share a held note
  until their last voice ends. Instrument routing, independent unison attacks,
  full voice/staff accidental semantics, ties/repeats/expression and mixer
  controls remain pending. This is timing/playback foundation, not complete
  notation or MuseScore parity.
- Automated verification: the final full suite passed **712 tests** with
  `flutter test --no-pub --concurrency=2 --reporter expanded`. The focused
  timeline, polyphonic playback, review and ensemble-transport run passed
  **21 tests**. Static analysis across `lib` and the new tests reported
  **no issues**; formatting and `git diff --check` passed.
- Physical validation on the connected Realme RMX1851 (Android 11/API 30):
  release build **2002**, installed as an update with app data retained. Imported
  a two-part, four-bar MusicXML score containing whole notes, quarters and
  triplet eighths; checked shared-bar scrubbing, play/pause/stop, keyboard
  command search with the soft keyboard, focus-selected-bar, pitch editing,
  undo, local project save and reopen. Android's audio service showed an active
  NoteVision speaker track with zero underruns at capture; this does not
  establish subjective sound quality. No app exception or overflow appeared
  in the inspected process log. Saved test project: `NV Ensemble Timing QA`.
  Native DocumentsUI search is unsupported on this device; keyboard navigation
  selected the test file successfully. No iOS device test was performed.

## Engine adapter assessment and next step

The inspected upstream [engraving build](https://github.com/musescore/MuseScore/blob/main/src/engraving/CMakeLists.txt)
defines a framework module with bundled engraving/font resources, the score
document model, editing commands and rendering/playback code. It links
`muse::draw`, with Qt Quick integration conditional on Qt support. Its
`ENGRAVING_NO_INTERNAL` option also disables interactive editing and the API, so
that option cannot by itself deliver the requested full editor. The root
[build](https://github.com/musescore/MuseScore/blob/main/CMakeLists.txt) uses the
Muse framework and C++20. These are inspected build boundaries, not proof of a
working mobile port. No MuseScore source or assets have been copied into the app.

**Decision (2026-10-28, user):** do not port or translate the MuseScore engine
(GPLv3, large C++/Muse framework). Instead study MuseScore Studio's features,
behavior and UI/UX (handbook, the running app, documented algorithms) and
implement them natively in NoteVision's Dart model and painter. Write our own
code; do not copy or line-by-line translate MuseScore source. The Leland font
(SIL OFL) may be used for glyphs.

## MuseScore comparison tests

`test/musescore_parity/` checks Note Vision against MuseScore Studio 4.7.5
(AppImage at `~/Applications/`, run headless). `cases/` holds hand-written
MusicXML scores, one feature family each. `tool/musescore_reference.sh
[case ...]` makes MuseScore import each case and export `reference/` MusicXML
and MIDI. The test imports MuseScore's file, saves and reopens it as a
project, exports MusicXML from the model alone (no retained source) and builds
playback; both sides are reduced to facts (`parity_facts.dart`) and compared.
`baseline/<case>.txt` lists the remaining differences (`-` MuseScore only,
`+` Note Vision only) with match counts. The test fails when that list
changes; after an improvement run `NV_UPDATE_PARITY=1 flutter test
test/musescore_parity` and commit the smaller baseline. A new feature starts
with a case: write it, generate its reference, record the baseline, then
implement until its differences are gone.

`transpositions.json` lists edits MuseScore can make from the command line
(`--transpose`, same JSON options as its Transpose dialog). The script writes
`reference/transpose/<name>.musicxml`; the test applies Note Vision's
`Transposer` with the same options to its import of the untransposed case and
compares key signatures, pitches and written accidentals (`pitchFacts`).

Initial gaps (2026-10-28): measure rests, pickups,
cut/common symbols, grace notes,
articulations, ornaments, dynamics, text, tempo, rehearsal marks, chord
symbols, lyrics, the second staff's clef (the model has one clef per bar)
and hidden gaps within a voice (`<forward>`; no invisible rests) are lost in
the model's export. Fixed since: the exporter writes `<staves>` and
`<backup>`/`<forward>` between voice/staff lanes, and the importer no longer
invents composer "Unknown composer", and written accidentals, final
barlines and voltas are exported.
Playback (now compared with velocities) lacks grace notes, chord-symbol playback and
instruments. Rhythm, pitch, beams, chords, meters and key handling match.

## Stage 3A — keyboard note input and chords

- MuseScore-style letters: in note entry (N) A–G writes a note of the chosen
  value after the input position (the selection and its chord tones, else the
  end of the selected bar), in the octave nearest the selected/previous note
  or the clef's middle line; 0 writes a rest. A full bar continues at the start
  of the next bar, appending one at the end of the score (one undo step).
  Outside note entry a letter re-pitches the selected note. `.` in note entry
  dots the note just written (MuseScore sets the dot before typing).
- Chords: Shift + A–G adds that letter above the selected note; Alt + 2–9
  adds an interval above it; the new tone is selected so intervals stack.
  "Add third above" is a searchable command and an Edit-dock button (Add 3rd).
  Input and chord additions continue the selected voice/staff.
- Fixed: deleting a chord's main note now promotes its next tone (it used to
  attach the remaining tones to the preceding note); insertion after a chord
  base goes after its tones.
- Not yet: MuseScore's overwrite-in-place input (we insert; a full next bar
  refuses input), ties across bar lines for values that do not fit,
  voice selection (Ctrl+Alt+1–4), and touch chord entry by tapping a pitch.
- Tests: `test/features/editor/domain/note_input_test.dart`, keyboard test in
  `editor_commands_test.dart`; full suite 734 passed, analysis clean.

## Stage 3B — transpose

- `Transposer` (`lib/core/services/transposer.dart`) follows MuseScore's
  Transpose dialog: to a key (closest/up/down), by any of its 25 intervals
  (up/down, optionally leaving key signatures), or diatonically along the
  scale keeping each note's alteration from the key; double sharps/flats
  optional, otherwise respelled. Pitches move as heard (key and carried
  accidentals included) and accidentals are rewritten for the new key. A key
  past seven sharps/flats becomes its enharmonic key while notes keep the
  interval's spelling, as MuseScore does. Scan evidence, review IDs, beams and
  rests are kept; a first bar without a key signature gains one.
- All ten MuseScore transposition references match exactly (keys, pitches and
  written accidentals), including mid-score key changes, chords and a grand
  staff. Editor: More → Transpose… and command search, one undo step,
  selection kept; the sheet fits phones with large text.
- Not yet: transposing only a selection (needs range selection, 3C), chord
  symbols (not in the model), transposing instruments.

## Stage 3C — range selection and clipboard

- `EditorState.rangeAnchor` holds the other end of a range in the selected
  part; every edit, undo or plain selection drops it (only range-aware
  actions pass it on). `selectionPositions` lists the range in reading order
  with the last chord's tones. The painter highlights every symbol in it.
- Keys: Shift + ←/→ and Shift + tap extend by a symbol, Ctrl/Cmd + Shift +
  ←/→ by bar, Ctrl/Cmd + A selects the staff, Ctrl/Cmd + C/X/V copy, cut,
  paste, Delete removes the range. Touch: Edit dock Selection row (Extend —
  a one-shot stand-in for Shift — Select bar, Copy, Cut, Paste; Paste also
  when a bar without a selection is chosen). Commands: Select all, Select
  bar, Copy, Cut, Paste in search.
- Paste goes bar by bar (empty bars kept): over a range (replacing it), else
  after the selection or at the end of the selected bar; later clipboard bars
  start the following bars, appended as needed. A bar that would overflow its
  time signature refuses the whole paste with a message. Copies carry no
  review ID or scan evidence; a copy starting inside a chord starts a chord.
  The pasted music is selected; one undo step. The clipboard lasts for the
  editing session.
- With a range, pitch and octave moves apply to every note (diatonic / octave
  transposition), and Transpose offers the selection: notes outside it keep
  their pitch but their written accidentals are recomputed (an unselected F
  after a transposed F# gains a natural). Single-note tools are disabled.
- Not yet: MuseScore's overwrite paste into occupied bars (we insert),
  multi-staff ranges, system clipboard / MusicXML interchange, range-wide
  duration and accidental edits.
- Tests: `range_selection_test.dart`, keyboard and touch range tests in
  `editor_commands_test.dart`; full suite passing, analysis clean.

## Stage 3D — voices

- `VoiceLayout` (`lib/core/widgets/score_notation/voice_layout.dart`) is
  shared by the editor painter, hit targets, playhead and PDF. In a bar with
  several voices, symbols that start together share a column; odd voices stem
  up and even voices down (beams follow); rests move two staff spaces up or
  down. Single-voice bars keep their previous sequential columns exactly.
- Input: Add notes has Voice 1–4 chips (MuseScore's voice colours) and
  Ctrl/Cmd + Alt + 1–4. A different voice from the selection starts where the
  selected symbol starts: rests fill that voice up to there (largest values
  first, dotted allowed), as MuseScore does; later input continues that voice
  and moves to the next bar when it is full. Tap and drag insertion use the
  chosen voice too. The choice resets when note entry closes.
- Not yet: moving existing notes to another voice, voice colouring of
  selected notes, collision handling for unisons/seconds between voices, and
  hiding or deleting the filler rests MuseScore can make invisible.
- Tests: `test/core/widgets/voice_layout_test.dart`, voice entry in
  `note_input_test.dart`, voice chips in `editor_commands_test.dart`; editor
  and PDF output were checked visually.

## Stage 3E (part 1) — staves and instruments

- More → Staves and instruments…, command search, or Bar tools → Clef →
  Staves opens `StavesSheet`, MuseScore's Instruments panel for one staff per
  part: add an instrument (name and usual clef; alto/tenor stay behind
  `AppFeatures.cClefs`), rename, reorder and remove. The sheet edits a working
  list; Done applies `rearrangeParts` as one undo step, Cancel changes
  nothing. New staves copy every bar's meter, key, breaks and barlines and
  start empty; adding one makes the parts play together.
- Scanned scores with several staves are lines of one part read in order, so
  adding an instrument there is refused with an explanation; renaming,
  reordering and removing still work. A one-staff score (including a new
  blank score) can gain instruments.
- Fixed (affected all editing since review IDs were introduced): assigning
  review IDs rebuilds every symbol, which silently cleared the selection after
  any edit that added a symbol or bar. Typed notes then went to the end of
  the bar instead of after the previous note. `_updateState` now finds the
  selection again by position.
- Not yet: instrument sounds (one piano channel; Stage 5 mixer), grand staff
  (next), transposing instruments, linked parts.

## Stage 3E (part 2) — grand staff

- A grand staff is two linked parts: `Part.staff` 2 continues the part above
  it. Every editing tool already works per part, so selection, input, clefs,
  transposition, ranges and voices need no grand-staff special cases. Every
  part rebuild carries `staff`.
- MusicXML import splits a `<staves>` part into linked parts with their own
  numbered clefs; symbols keep their staff/voice numbers; source bindings,
  duration checks and the playback timeline still address the original
  `<part>` (the timeline reads its events per staff). An unchanged import still
  exports the retained file.
- Export merges linked parts into one `<part>` with `<staves>`, numbered clefs
  and `<backup>`; symbols without a staff go on their staff in voices 5–8 for
  staff 2 (as MuseScore writes).
- Editor and PDF draw a brace, barlines through both staves and bar numbers
  once. Staves and instruments adds Piano as a grand staff; moving a lower
  staff away from its upper staff makes it independent.
- Parity: `16_grand_staff` now matches MuseScore except the final barline
  style; its transposition (T08) and playback match fully. Four older tests
  that assumed the two-staff fixture imports as one part now check the split.
- Not yet: cross-staff notes and beams, a grand staff from scans, staff
  spacing controls.

Device check (2026-10-28, Realme RMX1851, Android 11): release 2003 installed
as an update with projects retained. On a new blank score: N + letters wrote
notes in the nearest octave; selecting a note and typing inserted after it
(confirms the selection fix); Add 3rd stacked a chord; Select bar → Copy →
tap an empty bar → Paste copied the chord too and selected the paste;
Transpose on the selection moved only those notes with correct sharps; Staves
and instruments added a braced piano grand staff; save and reopen kept all of
it. Playback threw a RangeError on every frame in empty bars (playhead with
symbol -1, a Stage 3D regression); fixed in `ecc0a6b` with a test, and
release 2004 played the same project with no errors. No iOS device test.

## Stage 4A — ties and slurs

- `Score.spanners` holds ties and slurs as MuseScore spanners: kind plus the
  review IDs of the first and last note. Review IDs survive note rebuilds,
  undo and saving, so no note rebuild can drop them; a spanner whose notes
  are gone is ignored (and returns with undo). `SpannerIndex` finds the live
  ones (same part, in order; a tie also needs the same staff position).
  Spanners are part of `notationProjection`.
- Import: slurs pair by `number` within a `<part>`; a tie joins the next note
  in the same voice with the same pitch that ends a tie. Export writes
  `<tie>`, `<tied>` and numbered `<slur>`s (overlapping slurs get different
  numbers). A spanner change makes an imported file unpatchable, so it is
  rebuilt from the model (simple files) or refused with an explanation
  (complex files) instead of silently losing the change.
- Playback: a tied chain sounds once, held to the end of its last note.
- Editor: + ties the selected note to the next note of the same pitch in its
  voice (or unties); in note entry + writes a tied note of the same pitch.
  S slurs a range, or the selected note to the next note in its voice; the
  same slur again removes it. Edit dock Tie and Slur tiles, search commands.
- Drawing (editor and PDF): thin crescents on the side away from the stems;
  across a line break each half is drawn open at the row edge.
- Parity: `05_ties_slurs` now matches MuseScore in notation (15/15) and
  playback (9/9).
- Not yet: copying ties/slurs with copy/paste, ties for every note of a
  selected chord at once, slur shape around high notes in between, laissez
  vibrer and cross-staff slurs.

## Stage 4B — tuplets

- `Note` and `Rest` gained `copyWith` (every field kept unless given), and
  every place that copied a note field by field now uses it, so new fields
  (tuplets now; articulations and lyrics next) cannot be dropped by a copy.
  Edits still clear scan confidence, as before.
- `Tuplet` (actual:normal plus bracket start/stop) on a note or rest. Every
  length calculation goes through `symbolQuarters` or the timeline's exact
  `writtenDuration`, which apply the ratio: playback, bar capacity, voice
  alignment, beat grouping, the notation checker, the genre model.
- Import reads `<time-modification>` and `<tuplet>`; imported tuplets no
  longer force preservation-only handling, because the model now times them
  exactly. Export writes them, with `<divisions>` raised to 8 × the tuplet
  sizes' least common multiple (24 for triplets) so durations stay whole.
- Editor: Ctrl/Cmd + 3, 5, 6, 7 (and a Triplet tile and command) fill the
  selected note or rest's time with that many shorter notes (3:2, 5:4, 6:4,
  7:4); the first keeps the note, the others are rests. In note input a
  letter writes over the next rest of a tuplet, keeping its rhythm.
- Drawing (editor and PDF): the number above, with a bracket unless every
  note is beamed.
- Fixed while adding this: duration and dot checks converted lengths to
  decimals, which threw while building the editor for a tuplet note; they
  now time a candidate copy exactly.
- Parity: `06_tuplets` now matches MuseScore in notation (22/22) and
  playback (17/17).
- Not yet: nested tuplets, tuplets of dotted values, duplets in compound
  time, removing a tuplet in one step, proportional spacing (a bar of
  triplets is crowded in the fixed grid).

## Stage 4C — articulations and ornaments

- `Note.marks` / `Rest.marks` (`Articulation`: staccato, staccatissimo,
  tenuto, accent, marcato, fermata, trill, mordent, inverted mordent, turn),
  kept in a fixed order. Import reads `<articulations>`, `<ornaments>` and
  `<fermata>`; export writes them. Changing marks makes an imported file
  rebuild rather than patch.
- Playback as MuseScore plays them (checked against its MIDI): staccato half,
  staccatissimo 33%, marcato two thirds; trills alternate with the note above
  in 32nds; mordent note–below–note, inverted mordent note–above–note, turn
  above–note–below–note; neighbours follow the key signature.
- Editor: Shift+S / N / V / O (staccato, tenuto, accent, marcato), search
  commands for all, and an Edit-dock Marks row whose tiles show when the
  whole selection has a mark. Marks toggle on every selected note (chord
  tones share their chord's); a fermata also goes on rests.
- Drawing: `mark_glyphs.dart` gives shared shapes and placement — near-head
  marks on the side away from the stem, ornaments and fermatas above the
  staff and stems — drawn by both the editor and the PDF.
- Parity: `10_articulations` notation 16/16, playback 31/32; the remaining
  difference is under 2 ms (MuseScore releases each note a tick early, which
  moves its 33% staccatissimo across the comparison grid).
- Not yet: dynamics-driven velocity, accent loudness, fermata hold time,
  trill with accidental, technical marks (bowings, fingerings), marks on
  individual chord tones.

## Stage 4D — dynamics and hairpins

- `Note.dynamicMark` / `Rest.dynamicMark` (MusicXML names: p, mf, sfz…);
  hairpins are `SpannerKind.crescendo` / `diminuendo` spanners from their
  first note to their last (one note allowed; rests can be ends).
- Import: a `<direction>` dynamic belongs to the next note or rest on its
  staff; a wedge runs from the next note after its start to the last note
  before its stop. Export writes them as `<direction>`s before the note, and
  a wedge stop after its last note, as MuseScore writes it.
- Playback velocity (new `PlaybackEvent.velocity`), matched to MuseScore's
  MIDI: levels pp 33, p 49, mp 64, mf 80 (also the default, was a flat 90), f
  96, ff 112; sfz/sf/fz stress one note (112), fp/sfp drop to p after it; a
  hairpin glides over time to the next dynamic in its direction, else one
  level further, truncating like MuseScore; accents and marcatos play one
  level louder. The comparison tests now also compare every note's velocity
  with MuseScore's MIDI.
- Editor: < and > (crescendo / diminuendo over the selection or the
  selected note, toggling), an Edit-dock Dynamics row (pp p mp mf f ff sfz on
  the first selected note, toggling; Cresc. / Dim.), and search commands.
- Drawing (editor and PDF): dynamics in bold italic below the staff (lower
  under low notes), hairpins on the same line; split across line breaks.
- Parity: `11_dynamics` notation 23/23 and playback 19/19 (velocities
  included); `10_articulations` playback 62/63.
- Not yet: dynamics on a separate line aligned across a system, expressive
  text (cresc., dim. words), crescendo of a single held note in playback
  (MuseScore uses controller 2), dynamics for chord tones individually.

## Stage 4G — repeats, endings, jumps and barlines

- `Measure` gains `endingStart` (ending numbers, e.g. `[1]`, `[1, 2]`),
  `endingEnd` (`EndingEnd.closed` / `open` bracket) and `navigation`
  (`NavigationMark`: segno and coda where a bar starts; Fine, To Coda, D.C.,
  D.S. and their al Fine / al Coda forms where it ends). `BarlineType` adds
  `doubleBar` and `finalBar`. Bars are copied with `Measure.copyWith`.
- Playback: `ScoreTimelineBuilder.playOrder` unrolls repeats, endings and
  jumps as MuseScore plays them: a repeat plays as many times as its highest
  ending number (at least twice); after a D.C./D.S. repeats are not taken
  again and only the last ending plays; al Fine stops at Fine, al Coda jumps
  from To Coda to the coda. `build(score, unrollRepeats:)` uses it for
  sequential and simultaneous parts; review audition plays bars as written.
- MusicXML: endings (`<ending>` start/stop/discontinue), repeats, light-light
  and light-heavy bar styles, segno/coda symbols and jump words with
  `<sound>` attributes, both ways. MuseScore writes `<sound fine="yes"/>`
  under its segno, coda and To Coda markers; the importer trusts the symbol
  or words instead.
- Editor: Bar tools → Repeats (start/end repeat, 1st/2nd ending, double and
  final barline, segno, coda, To Coda, Fine, D.C., D.C. al Fine, D.S., D.S. al
  Coda) toggles on the selected bar or range in every staff, one undo step;
  a bar keeps one jump. The same signs are in command search. Drawn in the
  editor and PDF from shared `barShapes` (ending brackets with their numbers,
  barline styles, segno/coda signs and jump text).
- Parity: MuseScore's MusicXML import turns D.C./D.S. into plain staff text,
  so `17_segno_coda` and `18_endings_dc_al_fine` are native `.mscx` cases
  (`tool/musescore_reference.sh` accepts them). `14_repeats_voltas` 14/14 and
  13/13, `18_endings_dc_al_fine` 17/17 and 19/19, `17_segno_coda` playback
  15/15 and notation 14/16 (MuseScore exports the segno and coda after the
  bar's notes; ours sit at its start). `01_note_values` now matches its final
  barline.
- Not yet: D.C./D.S. that repeat repeats ("play repeats"), more than two
  endings from the editor (import keeps them), custom jump text, repeat counts
  other than ending numbers (MuseScore's "play count").

## Stage 4E — lyrics

- `Note.lyrics` contains `Lyric` values: verse number/name, Unicode text,
  single/begin/middle/end syllabic state, start/continue/stop extension lines,
  above/below placement and visibility. JSON is additive: older projects still
  open with no lyrics. Note copies, pitch edits and the clipboard keep lyrics.
- MusicXML reads/writes multiple `<lyric>` elements per note. Each imported
  lyric also retains its XML, preserving elisions, formatting, named verses and
  extra lyric metadata through saves and generated export. Replacing a syllable
  keeps its first text run's formatting; other verses stay intact. Lyric edits
  patch the retained document, keeping unrelated unsupported notation. Simple
  files containing lyrics can also rebuild after rhythm edits.
- Editor: Edit → Lyrics, Ctrl/Cmd+L, or command search opens a draft entry
  panel with a selected-bar preview. Space/Next word advances; `-`/Hyphen links
  syllables; `_`/Extend holds across notes. Pasting several words/syllables
  fills successive notes. Entry stays in the selected voice/staff, skips rests
  and chord tones, and skips tied continuations except when extending. Verse
  number/name, syllabic state and extension endpoints can be edited directly.
  Apply commits the session as one undo step; Cancel/dismissal keeps the score.
  Applying retains note selection and rechecks playback/review/stale-score locks.
- `LyricLayout` shares text/connector geometry between screen and PDF: centered
  syllables, verse rows, hyphens and melismas split at system/page boundaries.
  Clicking lyric text selects its note. Additional verse/voice rows reserve
  vertical space and reduce systems per page consistently in editor and PDF;
  pagination also reserves room for the first-page heading.
- MuseScore Studio 4.7.5: `13_lyrics` now matches **10/10 notation facts** and
  **11/11 playback facts**. Separate tests cover explicit extension endpoints,
  retained-source edits, rich lyric XML, project saves, copy/pitch preservation,
  voice/tie navigation, undo/cancel, paste, text selection and responsive entry.
- Verification: full Flutter suite **822 passed** (`flutter test --no-pub
  --concurrency=2 --reporter expanded`); `flutter analyze --no-pub` reports
  **no issues**; `git diff --check` clean. This is automated/widget verification;
  no new on-device mobile release was tested for this stage.
- Visual inspection: phone, 320px/2× text, landscape and tablet entry panels;
  generated PDF checked visually and with text extraction. Artifacts can be
  regenerated with `NV_EDITOR_SCREENSHOTS=/tmp/note-vision-lyrics flutter test
  --no-pub test/features/editor/presentation/lyrics_test.dart
  test/features/pdf/lyrics_test.dart`.
- Not yet: lyrics on rests, inline text editing, lyric-only clipboard commands,
  style/formatting controls, reserved-character shortcuts, or proportional
  spacing/collision avoidance for long syllables in dense fixed-grid bars.
  Rich imported text formatting is preserved in XML; the canvas/PDF use the
  common lyric font. Scanning does not recognize lyrics.
- References: [MuseScore lyrics workflow](https://handbook.musescore.org/text/lyrics),
  [MusicXML lyric](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/lyric/)
  and [extension types](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/extend/).

## Stage 4F — text, tempo and chord symbols

- `Measure.annotations` contains beat-attached `ScoreAnnotation` values for
  staff/system text, rehearsal marks, tempo and chord symbols. Offsets are exact
  quarter-note ratios and remain independent of notes, including in empty bars.
  JSON is additive; measure copies and ordinary edits keep annotations.
- MusicXML import follows the source cursor, divisions, backup/forward and
  offsets, including split grand staves. Complete original direction/harmony
  XML is retained. Editing/removing a marking patches its source element without
  deleting a dynamic, pedal or other direction sharing it. Simple fully modeled
  text/harmony files can rebuild after rhythm edits. Offsets unrepresentable in
  a complex source's original divisions fail explicitly; project saving retains
  the exact value. Generated exports raise divisions for rational offsets.
- System directions use **MusicXML 4.0**; generated plain notation remains 3.1,
  and rebuilding a 4.0 source keeps version 4.0. This avoids claiming 3.1 while
  writing the 4.0 `system` attribute.
- Editor: Edit → Text & tempo, searchable commands, Ctrl/Cmd+Alt+T (tempo)
  and Ctrl/Cmd+Alt+K (chords; Ctrl/Cmd+K stays command search). The draft panel
  lists the bar's markings, with add/edit/remove, beat, text, beat unit/dots/BPM
  and chord entry. Shortcuts edit an existing marking at that beat. Apply is
  one undo step; Cancel/dismissal does nothing. No-op Apply, pending edits when
  deleting another marking, selection and playback/review/stale-score locks
  are covered. Beat numbers follow the active meter's denominator.
- `AnnotationLayout` shares screen/PDF placement and annotation hit targets.
  System markings route to the top staff; clicking opens their original owner.
  Rehearsal marks are boxed; separate text lanes reserve vertical room and use
  matching editor/PDF pagination. Header export remains available for bars with
  annotations alone.
- `TempoMap` integrates written quarter-note BPM over musical time, including
  changes inside held notes, dotted/other beat units, repeats/jumps, shared
  ensemble tempo and scanned-line reading order. Scheduler boundaries, scrubber
  durations and seeking use the same map. With written tempos, transport shows
  **100%** at its old 120 setting and adjusts relative speed without changing
  the score; unmarked scores keep the existing BPM control.
- `ChordSymbol` parses common major/minor, seventh, sixth, ninth, suspended,
  diminished/augmented/power chords, accidentals and slash basses; `N.C.` stops
  the previous chord. Supported kinds realize piano bass/chord voicings until
  the next harmony or bar end, without taking over note highlights. Transpose
  moves roots and slash basses along with notes (range edits match selected
  onsets). Unsupported kinds/degrees retain their XML and are not guessed for
  accompaniment.
- MuseScore Studio 4.7.5: `12_text_chord_symbols` now matches **21/21 notation
  facts** and **51/51 playback facts**. All 28 comparison/transposition cases
  pass. Scheduler tests also check actual elapsed time through a mid-note
  tempo change and the end of a review passage with later tempo changes.
- Verification: **849 passed** with `flutter test --no-pub --concurrency=2
  --reporter expanded`; `flutter analyze --no-pub` reports **no issues**;
  `git diff --check` clean. This is automated/widget verification.
- Visual inspection: phone, 320px/2× text, landscape and tablet entry panels;
  PDF inspected visually and with text extraction. Regenerate with
  `NV_EDITOR_SCREENSHOTS=/tmp/note-vision-4f flutter test --no-pub
  test/features/editor/presentation/annotations_test.dart
  test/features/pdf/annotations_test.dart`. No new on-device release was tested.
- Not yet: inline editing, annotation-only clipboard, rich text styles,
  proportional spacing/collision avoidance, note-glyph metronome engraving
  (beat units are readable names), metric modulations/tempo ramps, standalone
  measure `<sound>` tempo editing, Roman/Nashville/microtonal/polychord entry,
  altered-degree accompaniment or configurable voicings/instruments. These
  unsupported imported elements remain in retained source.
- References: [MuseScore tempo](https://handbook.musescore.org/text/tempo-markings),
  [chord symbols](https://handbook.musescore.org/text/chord-symbols),
  [MusicXML directions](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/direction/)
  and [harmonies](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/harmony/).

## Stage 4H (part 1) — bar rests, pickups, common and cut time

- `Rest.measureRest`: a whole-bar rest (`<rest measure="yes"/>`, written
  without `<type>` as MuseScore writes it). Its type and dots still give its
  length; any change of length makes it an ordinary rest (`copyWith`). Drawn
  as a whole rest centred in the bar in every meter, editor and PDF. Bar
  tools → Measures → Bar rest (and search) fills an empty or rests-only bar
  of the selected staff; refused where no single value fills the meter
  (5/4).
- `Measure.implicit`: a pickup or other bar left out of the count
  (`implicit="yes"`). Bars are numbered as MuseScore numbers them: a leading
  pickup is 0 and is not labelled; inserting, deleting and appending bars
  keep the count. Bar tools → Measures → Pickup (and search) toggles it in
  every staff.
- `TimeSignature.symbol` (`TimeSymbol.common` / `cut`, `TimeSignature.common`
  and `.cut`): imported and exported as `<time symbol>`, drawn as C / ¢ in
  editor and PDF, saved in projects; the scanner's C and cut-time detections
  now keep their sign. Bar tools → Time adds C and ¢ beside 4/4 and 2/2.
- `valueForQuarters` (note_value.dart) is shared by the importer and the
  editor.
- Parity: `01_note_values` 20/20 and 17/17, `03_clefs_meters` 23/23 and
  13/13 (both were missing bar rests, pickup and C/¢).
- New case `19_grace_timing` records MuseScore's grace-note timing for part
  2. MuseScore's MIDI export writes appoggiaturas and acciaccaturas with no
  length or not at all, but moves the main notes: an appoggiatura takes its
  value (at most half the main note) from the main note's start; an
  acciaccatura takes the same from the end of the note before; several grace
  notes share one grace note's time.

## Stage 4H (part 2) — grace notes

- `Note.grace` (`Grace.appoggiatura` / `acciaccatura`): written before its
  main note, it takes no time in the bar (`symbolQuarters`,
  `writtenDuration`), so capacity, onsets and checks are unchanged. Imported
  from `<grace>` / `<grace slash="yes"/>` (previously dropped) and exported
  without `<duration>`, keeping grace beams. Retained-source timing already
  read grace notes; they are now bound and editable.
- Playback (`_applyGraces`), measured from MuseScore 4.7.5 (case 19): a
  group takes one grace note's value, at most half the note it borrows
  from, shared equally. An appoggiatura borrows from the start of its main
  note (which starts later); an acciaccatura from the end of the note
  before, across a barline too. MuseScore's MIDI export writes grace notes
  with no length or leaves them out, but its main-note timings show the
  rule; we sound the grace notes. With no note before (score start), an
  acciaccatura sounds over the start of its main note.
- Editor: Edit → Acciacc. / Appogg. tiles and search commands add an eighth
  grace note at the selected note's pitch before it (before its chord) and
  select it; on a grace note they change its kind. Lyrics skip grace notes;
  beams and the genre model ignore them; multi-voice layout puts them just
  before their main note.
- Drawing (editor and PDF): 65% size, stem up and flagged, slashed for an
  acciaccatura (`graceScale`).
- Parity: `09_grace_notes` notation 12/12, playback 8/9; `19_grace_timing`
  28/28 and 30/31. The one playback difference in each is the opening grace
  note, which MuseScore's MIDI gives no length; the extra Note Vision facts
  are grace notes its MIDI omits.
- Not yet: grace notes after a note, grace chords, beamed grace drawing (each
  is flagged), proportional spacing (a grace note takes a full column; 4I).
  MuseScore plays an imported underfull bar at its written length; we keep
  the meter's length.

## Stage 5A — instrument sounds and mixer

- More → **Mixer…**, command search and **F10** open a draft panel: 128
  General MIDI bank-0 sounds, volume percentage, stereo pan, mute and solo.
  Apply creates one undo step and keeps the notation/selection; Cancel and
  dismissal are inert. Opening/applying respects playback, loading, review
  and stale-score locks. Changes take effect on play or resume, not live.
- `Part.playback` stores `PartPlayback` in project JSON. Legacy projects
  default to piano. Ordinary edits, measure operations, transposition,
  review restoration, staff rearrangement and scan append keep the mix.
  Newly added instruments get an appropriate program; a rename keeps the
  chosen sound. Linked grand staves share one strip, and sequential scanned
  lines share one strip without changing their reading order.
- `PlaybackMix` routes each audible instrument to its own MIDI channel;
  channel 10 remains reserved for percussion. Up to 15 sounding instruments
  are supported; larger ensembles explain the limit instead of sharing
  sounds. Several solo strips can sound together; explicit mute wins.
  Silence does not change timing, position highlights or score content.
- The scheduler configures programs, channel volume (CC7) and pan (CC10)
  before attacks. Overlapping pitches are counted by **channel and key**,
  so one instrument cannot stop another instrument's note. Pause/stop,
  cancelled sound loading, retry after configuration failure, changed mix
  on resume and resetting controllers between scores are covered by tests.
- MusicXML single initial pitched GM programs, volume and pan are read in
  partwise/timewise scores and shared across split grand staves. Export uses
  one-based programs and matching score-instrument/MIDI IDs. Sound edits
  patch only changed fields in retained XML, preserving notes, devices,
  instrument IDs and other metadata. Generated declarations remain safe to
  rebuild after rhythm edits on simple reimported scores. Mute and solo are
  project-only and do not silence MusicXML notation.
- MuseScore Studio **4.7.5**: existing `15_ensemble` now matches flute/cello
  programs (12/18 playback facts, previously 10/18). New `20_instrument_mix`
  matches 16/16 notation facts and 7/11 playback facts, including all three
  chosen programs. Separate assertions verify MuseScore's quantized CC
  volumes (63/95/127) and left/right/center pan through project save and
  generated export. Remaining differences are wind/string note releases
  and MuseScore's additional string program declarations, not full sound
  equivalence.
- Responsive widget checks cover phone, 320px/2× text, landscape and tablet,
  plus sound selection, undo, cancel/no-op and playback locks. Screenshots:
  `NV_EDITOR_SCREENSHOTS=/tmp/note-vision-5a flutter test --no-pub
  test/features/editor/presentation/mixer_test.dart`. Phone and large-text
  screenshots inspected. MIDI tests use a recording backend; subsequent
  physical Android validation is recorded below. No iOS device test.
- Verification: **882 tests passed** with `flutter test --no-pub
  --concurrency=2 --reporter expanded`; `flutter analyze --no-pub` reports
  **no issues**; `git diff --check` clean. All 30 MuseScore
  comparison/transposition cases pass their recorded baselines.
- The existing local `piano.sf2` contains all 128 bank-0 presets. The file
  remains untracked; installations need a complete GM font, as documented
  in `assets/soundfonts/README.txt`. A piano-only replacement cannot supply
  the other sounds.
- Not yet: live mixer adjustments, master/effects/aux channels, reverb UI,
  metronome/loop controls, MIDI/audio export, mid-score instrument changes,
  non-GM banks, percussion mapping, separate voice or harmony strips and
  transposing-instrument notation. Unsupported imported instrument metadata
  stays in source; changing sounds in multiple-instrument, percussion or
  non-GM source declarations refuses preserving export explicitly.
- References: [MuseScore mixer](https://handbook.musescore.org/sound-and-playback/mixer),
  [MusicXML MIDI instrument](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/midi-instrument/).

Device check (2026-11-01): release **2005**, built from `f801e50` with
`flutter build apk --release --no-pub --target-platform android-arm64
--build-number 2005`, installed as an update on the Realme RMX1851
(Android 11/API 30). Both existing projects remained present.

- Imported a separate 12-bar flute/cello/piano grand-staff score. The four
  staves produced three mixer strips with the imported sounds and 75%
  volume. The two piano staves shared one strip.
- Changed the flute strip to Oboe, volume 50%, pan 45° left and Solo;
  the cello showed its solo-silenced status and the piano showed Muted.
  Apply made one undoable edit; Undo restored Flute/75%/center and Redo
  restored the edited mix. Native playback ran with the edited settings.
- Paused, changed the sound again to Tenor sax with 75% volume and 45°
  right pan, then resumed at the cued passage successfully. Mixer editing
  was disabled while playing. Stop/reset worked. Android's audio service
  showed the app's active 44.1 kHz stereo speaker track with **zero
  underruns** at both diagnostic captures. The user confirmed **clear
  audio** on the phone; this is not a timbre or stereo-calibration test.
- Saved **NV Mixer Phone QA**, force-stopped and cold-started the app,
  then reopened the project: Tenor sax/75%/45° right reloaded correctly.
  Cancelling a later pending volume change left 75% and the saved state
  intact. The QA project is left saved and open, with playback stopped.
- Inspected portrait, landscape and 1.8× system text layouts, including
  scrolling to mixer controls and reachable Apply/Cancel. Restored the
  original font scale (0.9), rotation preference and automatic rotation.
  No app crash, unhandled exception, playback/configuration error or
  overflow appeared in the inspected process logs. Captures and logs:
  `/tmp/nv5a-phone/`. Native DocumentsUI required keyboard navigation to
  select the file on this phone, as in the previous device check.

## Stage 4I — proportional spacing and collision handling

- Shared EngravingLayout / BarPlacement owns notehead and beat positions for
  the canvas, symbol/lyric/annotation targets, insertion/drop indicators,
  playhead and PDF. It uses the Stage 2B live rational timeline, preserving
  source gaps and distinct sub-1/960 onsets; text offsets stay rational,
  including thirds. Unsupported source edits retain an editable written
  preview without relaxing playback or preservation restrictions.
- Duration springs give doubled durations 1.5× the ideal extra spacing,
  constrained by glyph/text bounds. Onset columns are shared across staves
  and voices; grace groups get compact columns immediately before their
  main note. Whole-bar rests stay centered.
- Chord seconds alternate noteheads around a shared stem. Touching voices
  move apart; accidentals with overlapping vertical extents occupy separate
  columns. Chord stems and beams reach all their heads. Ledger lines follow
  the same staff grid in both renderers, including grace notes. Displaced
  chord tones can be selected directly.
- Horizontal bounds reserve room for accidentals, dots, ledger lines,
  visible lyrics and text. Same-kind text at the same beat stacks in separate
  reserved lanes. Vertical clearance accounts for notes, stems and marks,
  moving lyrics/text out of their way and keeping adjacent staves apart.
- EditorLayoutPolicy.forScore chooses up to four equal-width bars per row
  from the score's most demanding bar and reserves shared staff headroom.
  Exceptionally large bars/systems expand the logical page; PDF scales it
  uniformly onto A4. Automatic pages are added inside imported/manual page
  break sections when needed, preserving explicit breaks without clipping
  dense systems. The longest staff supplies layout page slots, so shorter
  parts neither crash the layout nor hide longer parts' final measures.
- Geometry and policy cache by immutable score/page identity; playback frames
  reuse them. Projects, note durations, source XML and audio conversion are
  unchanged; rendering saved projects needs no migration.
- Independent MuseScore Studio **4.7.5** case 21_engraving exercises mixed
  durations, dense beams, grace notes, lyrics, simultaneous text, chord
  seconds/accidentals and an overlapping voice. Its SVG was inspected beside
  the canvas/PDF. Semantic baseline: notation **40/41**, playback **40/75**.
  Existing differences include normalization of a courtesy natural, voice
  releases, coincident-pitch MIDI note-offs, and MuseScore holding chord
  accompaniment beyond the bar. This is not pixel or audio parity; all
  previous baselines are unchanged.
- Verification: **899 tests passed** with flutter test --no-pub
  --concurrency=2 --reporter expanded; flutter analyze --no-pub reports
  **no issues**; git diff --check clean. All **31** MuseScore comparison /
  transposition cases pass their recorded baselines. New tests cover rational
  source gaps/thirds, grace spacing, aligned staves, chord/accidental/stem
  geometry, word bounds, text lanes, head selection, extreme-pitch headroom,
  uneven part lengths, ledger lines and overflow pagination.
- Canvas/PDF fixture: NV_EDITOR_SCREENSHOTS=/tmp/note-vision-4i flutter test
  --no-pub test/features/pdf/engraving_test.dart. Both artifacts inspected;
  PDF text extracted. Editor control regressions also cover phone,
  small/large-text, landscape and tablet configurations.
- Device check (2026-11-03, release **2007**, Realme RMX1851 / Android 11):
  21_engraving imported and saved as **Engraving QA**; the editor shows one
  bar per row with compact grace notes, lyrics and stacked text clear of the
  notes, and chord accidentals in separate columns. The import preview and
  collection cards still used the old fixed grid (four bars crammed into a
  row); `ScorePageThumbnail` now uses `EditorLayoutPolicy.forScore` and the
  editor's layout measures (`score_page_thumbnail_test.dart`), confirmed on
  the phone. Android's picker ignored adb taps on file rows, so the file was
  picked by hand. On this 5 GB machine a release build with the project's
  4 GB Gradle heap was killed with the desktop session; build with
  `GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx2g -XX:MaxMetaspaceSize=768m'"`.
- Remaining: variable bar widths and per-system density, soft system breaks /
  system locks, user spacing/style controls, full optical engraving,
  automatic slur/tuplet/ending/navigation placement, advanced dot/rest/voice
  collision rules, cross-staff notation and beamed grace drawing. Conservative
  score-wide density/headroom can leave sparse bars with extra space. Very
  large logical pages produce smaller PDF notation when fitted to A4.
- References: [MuseScore spacing](https://handbook.musescore.org/formatting/score-size-and-spacing),
  [systems and horizontal spacing](https://handbook.musescore.org/formatting/systems-and-horizontal-spacing).

## Stage 5C — new-score wizard

- Collection → + → New Score opens `NewScoreWizard` (full screen, two steps)
  in place of the title/composer dialog. **Instruments:** your staves first
  (add from the Staves sheet's instruments, move up, remove), then MuseScore
  Studio's template groups: General (treble, bass, grand staff), Choral
  (SATB, SATB + Piano, Voice + Piano), Chamber music (string quartet), Solo
  (guitar, piano), Jazz (lead sheet). Treble clef is preselected, keeping
  the old quick path. **Score details:** title, composer, key (C♭–C♯ major),
  time (2/4 … 12/8, C, ¢), pickup (lengths one rest can fill), bars
  (default 32, as MuseScore) and an optional metronome mark (quarter,
  dotted quarter in compound time, half in 2/2).
- `buildNewScore(NewScoreOptions)` (pure Dart, `lib/features/new_score/`)
  builds the parts: grand staves as linked parts (`P1`, `P1-staff2`),
  default sounds, simultaneous playback, key/meter/clef on bar 1, a pickup
  as an implicit bar holding one rest, the tempo on the top staff.
- Octave clefs: `Clef.octave` (MusicXML `clef-octave-change`), drawn with a
  small 8; notes keep sounding pitch and only their staff position moves
  (`Clef.layoutSign`, e.g. `G-1`, read by `StaffPitchMapper`). Key
  signatures sit as on the plain clef. The Staves sheet's Guitar and the new
  Tenor use treble 8vb; Soprano/Alto were added. Voices now sound as GM
  choir aahs (MuseScore's program), and numbered parts ("Violin II") get
  their instrument's sound.
- Parity: MuseScore's own templates are exported to
  `reference/templates/` (`tool/musescore_reference.sh`), and
  `new_score_test.dart` checks each of ours has their part names, MIDI
  programs and clefs (all 10 match). New case `22_octave_clefs` (tenor and
  guitar): notation 17/17, playback 17/17.
- Device check (release **2009**, Realme RMX1851 / Android 11): SATB + Piano
  in B♭, 3/4, quarter pickup, tempo 120 created through the wizard; the
  first phone run showed the tenor's key signature an octave high, fixed and
  rechecked.
- Not yet: transposing instruments (clarinet, horn, saxophones) and their
  templates, percussion and tablature templates, subtitle/lyricist/
  copyright fields, saving user templates, minor-key names, irregular
  pickups needing two rests.

## Stage 5D (part 1) — transposing instruments and concert pitch

- `Part.transposition` (`Transposition`: diatonic, chromatic, octave — what
  is added to the written pitch, as MusicXML `<transpose>`). Notes and key
  signatures are stored as written; playback adds the interval unless the
  score is in concert pitch. Imported from and exported to `<transpose>`
  (previously ignored: imported clarinet parts played a tone high).
- Concert pitch: More → Concert pitch (checked) and command search, shown
  when a score has a transposing part. `Transposer.concertPitch` rewrites
  each transposing part by its own interval (key signatures included, then
  any extra octave), saved as `Score.concertPitch`, one undo step. Export
  always writes the players' parts.
- Instruments as MuseScore Studio names and transposes them
  (`transpositionFor`): Clarinet in Bb, Bass Clarinet, Soprano/Alto/Tenor/
  Baritone Saxophone, Trumpet in Bb, Horn in F, Piccolo, Glockenspiel, and
  an octave down for Double bass, Acoustic bass and Bass guitar; their GM
  sounds follow MuseScore. The Staves sheet adds clarinet, alto and tenor
  sax, trumpet in B♭, horn, bassoon and tuba; a new staff's key signature is
  written for its instrument.
- New-score templates: wind quartet, wind quintet, saxophone quartet, brass
  quartet and brass quintet, matching MuseScore's names, sounds, clefs,
  transpositions and written keys (concert C: clarinet in D, horn in G).
- Refactor: every field-by-field `Part(id: p.id, name: p.name, …)` copy now
  uses `Part.copyWith` (21 places), so new fields survive; several had been
  dropping a part's mixer settings.
- Parity: `23_transposing` (flute, clarinet, alto sax, horn, tenor sax on one
  concert melody): notation 45/45, playback 41/41. All 15 templates match.
- Not yet: chord symbols in transposing parts are not transposed for
  concert pitch or playback; per-instrument concert-pitch clefs;
  transposition changes mid-score.

Next: 5D part 2 — percussion (drum kit, unpitched staves), then tablature
and cross-staff notation. Retained-source rhythm export for complex documents,
global timewise measure slots and richer editable notation still need work;
continue using the Stage 2B timeline rather than adding flat-list timing rules.

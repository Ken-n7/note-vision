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
cut/common symbols, final barlines, voltas, ties, slurs, tuplets, grace notes,
articulations, ornaments, dynamics, text, tempo, rehearsal marks, chord
symbols, lyrics, the second staff's clef (the model has one clef per bar)
and hidden gaps within a voice (`<forward>`; no invisible rests) are lost in
the model's export. Fixed since: the exporter writes `<staves>` and
`<backup>`/`<forward>` between voice/staff lanes, and the importer no longer
invents composer "Unknown composer", and written accidentals are exported.
Playback lacks tie merging,
grace notes, repeats, articulation lengths, chord-symbol playback and
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

Next: Stage 4 — notation and engraving (ties, slurs, tuplets, articulations,
dynamics, lyrics, repeats, shared layout), starting from the parity gaps. (range selection and clipboard), 3D
(voices), 3E (instrument/staff management) on the Stage 2B timeline. Retained-source
rhythm export, global timewise measure slots and richer editable notation still
need work. Range/clipboard and advanced notation should build on this timeline
rather than adding more flat-list rules.

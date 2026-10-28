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

Initial gaps (2026-10-28): written accidentals, measure rests, pickups,
cut/common symbols, final barlines, voltas, ties, slurs, tuplets, grace notes,
articulations, ornaments, dynamics, text, tempo, rehearsal marks, chord
symbols, lyrics, grand-staff export (no `<staves>`/second clef/`<backup>`),
and second-voice export (no `<backup>`) are lost in the model's export; the
importer invents composer "Unknown composer". Playback lacks tie merging,
grace notes, repeats, articulation lengths, chord-symbol playback and
instruments. Rhythm, pitch, beams, chords, meters and key handling match.

Next: Stage 3 (selection and composition) on the Stage 2B timeline. Retained-source
rhythm export, global timewise measure slots and richer editable notation still
need work. Range/clipboard and advanced notation should build on this timeline
rather than adding more flat-list rules.

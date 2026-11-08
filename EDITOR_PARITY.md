# NoteVision notation editor

User-approved objective: MuseScore Studio-level editing capabilities **and UI/UX**
inside NoteVision, retaining offline mobile scanning and recognition. A handoff to
another app does not satisfy this objective. Work branch: `feat/musescore-editor`.

This is a multi-stage implementation. A completed stage is not full parity.
The user cancelled the automatic quota-reset trigger request. Do not install one.

## Current priorities — 2026-11-05

The user prioritized scan accuracy, easy corrections and reliable playback
while explicitly retaining full MuseScore parity as the long-term objective.
Work through the everyday offline flow before adding more advanced templates:

1. **Scan reliability and accuracy:** establish reproducible real-photo checks,
   retain the frozen model/thresholds until validated changes show a benefit,
   and fix failed, cancelled or retried scans. First slice: prevent stale scan
   results and release the native detector safely when leaving the screen.
2. **Easy corrections:** make uncertain/missing symbols easy to locate against
   the original page; verify preview, manual edits, undo and save/reopen.
   Measure changes against real scans rather than treating correct beat totals
   as evidence that recognition is correct.
3. **Reliable playback and export:** verify corrected pitches/rhythms, transport,
   persistence and MusicXML/PDF through the complete scan-to-export flow.

Use automated regressions and physical phone QA for each app change before
starting the next feature. The Symphony listening check is still deferred;
objective Android audio diagnostics do not establish subjective sound quality.
All remaining parity items below stay on the roadmap, including marching and
other templates, family brackets, advanced engraving and platform integrations.
This changes work order, not the full-parity objective or acceptance criteria.

### Scan lifecycle reliability — 2026-11-05

- `ScanViewModel` invalidates work when reset, superseded or disposed. Late
  successes/errors cannot replace the active photo's result. A new run clears
  previous detection/mapping output; results publish together after source
  evidence is ready. Leaving during preprocessing does not start detection.
- Replacement requests wait for an active detection before reusing the native
  model. Leaving during model loading/detection defers native cleanup until
  that operation completes, including its failure path. Disposed view models
  cannot start new work.
- Eight asynchronous regression cases reproduced failures before the fix and
  pass afterward. Focused scan tests: **12 passed**. Full suite:
  `flutter test --no-pub --reporter expanded` **1,022 passed**;
  `flutter analyze --no-pub` clean; `git diff --check` clean.
  Logs: `/tmp/note-vision-scan-lifecycle-{before,after}.log`,
  `/tmp/note-vision-scan-reliability-{analyze,tests}.log`.
- Detector weights, thresholds and reconstruction are unchanged. This is a
  reliability fix, with no recognition-accuracy improvement claimed.
- **Device QA passed:** local release **2020**, Realme RMX1851 / Android 11.
  Used handwritten photo `IMG_20261015_211254_063` from the existing labelled
  review set. Starting then immediately leaving a scan returned to Capture;
  its process log showed zero native detector initializations. A fresh scan
  completed with one initialization, eight traced staves and 240 symbols.
  Continued to the editor and visually checked original-image comparison.
  Saved **NVScan2020**; MusicXML contains eight parts, 171 notes and eight
  rests. A cold restart retained all 11 previous projects (12 total), and
  the reopened scan's export was byte-identical. A short playback smoke
  check showed an active 44.1 kHz stereo track with zero underruns; listening
  remains deferred. Inspected app logs contained no Flutter exceptions,
  rendering overflow or fatal exception. Display preferences unchanged;
  temporary keyboard helper and duplicate gallery copy removed. QA source
  photo/exports retained in `Download/NoteVisionQA2020/`; NVScan2020 left
  open with playback stopped. No iOS test.
  Evidence: `/tmp/note-vision-phone-2020/`, including `qa-facts.json`.
  Tested APK SHA-256:
  `5a61d5ad61c146431911ed87adef4f716c41be460025c29a73235d3ac6b59fb0`.
- Next: triage real-photo pitch/rhythm errors and the manual-correction
  workflow before selecting another change. Advanced parity items remain
  queued; detector calibration requires validation, not assumptions based on
  balanced bars or detector confidence alone.

### Original scan during manual correction — 2026-11-05

- Triage of archived B9 v2 A score pairs from 34 real photos: 27 have matching
  staff counts (3,006 reference notes/rests); seven staff-count mismatches
  were excluded from per-staff alignment. A deterministic edit-distance
  alignment gives 567 pitch-only substitutions, 172 length-only, 164 both,
  11 note/rest substitutions, 57 missing tokens and 268 extra tokens
  (1,239 edits, matching the archived 41.2% sequence error rate).
  This is a historical diagnostic proxy: references come from labelled
  boxes through the same reconstruction pipeline, written accidentals are
  omitted, and alignments are not unique. It is neither a fresh inference
  benchmark nor manually transcribed musical ground truth. Do not use it
  to calibrate detector thresholds. Reproduction/artifacts:
  `/tmp/note-vision-triage-2021/{triage.py,report.json}`; archived inputs:
  `note-vision-data/out/review_eval/scores/`.
- Concrete correction gap: Edit manually previously removed the source photo.
  It now opens a modeless original-scan reference beside/above the editable
  paper. More → Original scan opens it independently of checker findings.
  It follows selected symbols/measures and the attached page, with a full-page
  option for surrounding/missing notation, pinch zoom and a close button.
  Measures without source evidence show a message instead of the prior image.
- Reference visibility is workspace state, not a score edit. Musical edits,
  undo, save and source evidence retain their existing semantics. Changing
  crop/page resets its image viewport; ordinary pitch edits retain the view.
  Compact layouts allocate more space to the score/reference and retain a
  scrollable editing dock; the Review header remains available.
- Focused reference/review regressions: **18 passed**, including manual pitch
  editing/undo, page following, missing evidence, full-page/crop switching,
  evidence persistence and opening without changing the score. Captures at
  phone, 320×568, 1.8x text, landscape and tablet sizes were visually checked
  in `/tmp/note-vision-triage-2021/screens/`.
- Detector weights, thresholds, recognition and reconstruction are unchanged;
  no scan-accuracy improvement is claimed. Full parity remains queued.
- Final automated verification: `flutter analyze --no-pub` clean;
  `flutter test --no-pub --reporter expanded` **1,031 passed**;
  `git diff --check` clean. Logs:
  `/tmp/note-vision-triage-2021/{analyze-final,focused-final,full-tests}.log`.
- **Device QA passed:** local release **2021**, Realme RMX1851 / Android 11.
  Used saved **NVScan2020**. More → Original scan and Review → Edit manually
  both showed the original photo with editable paper and controls. Verified
  full-page/crop switching, the selected-symbol outline, and source tracking
  into Bar 2. Touch Up changed the first note G2 → A2; undo restored G2 and
  redo restored A2 while the reference stayed open. MusicXML differed only
  at that pitch. Saved A2, cold-restarted and verified a byte-identical
  exported score; the original-photo reference reopened successfully.
  Restored G2 with touch Down, saved and verified the baseline export
  byte-for-byte. All 12 projects retained. Enlarged text (1.8x) and landscape
  visually checked; inspected app logs had no Flutter exceptions/overflows.
  Font scale 0.9 and original rotation preferences restored, temporary
  keyboard helper removed, NVScan2020 left open with reference visible and
  playback stopped. No iOS test or new subjective listening confirmation.
  An early automated run was interrupted by auto-rotation; its unsaved QA
  input was discarded and baseline recovery verified before rerunning with
  portrait locked. Export automation now checks actual menu/dialog controls
  before typing. No app-code changes were needed during phone QA.
  Evidence: `/tmp/note-vision-phone-2021/` (including `qa-facts.json`);
  phone exports: `Download/NoteVisionQA2021/`. Tested APK SHA-256:
  `9a27d88c81add3e05609699375c27508c225a6ade2af1aa8f8ff8b7c311a4b65`.

### Scanned rows in reading order — 2026-11-05

- Reproduced NVScan2020's column-by-column pagination with its real-photo
  fixture: eight independently scanned rows were being painted as eight
  simultaneous parts. `ScoreDisplayProjection` now presents sequential scans
  row by row. The eight-row / three-bar case has one editor/thumbnail/PDF
  page, with each source row's bars adjacent. Existing saved scans update
  without rescanning or rewriting their music.
- Eligibility uses sequential playback plus scan evidence/legacy scan ID;
  imported MusicXML, simultaneous ensembles, grand staves, linked TAB and
  percussion retain their layouts. The display copy has an explicit map back
  to every original part/measure. Saved parts, notes, evidence and playback
  remain intact; it does not guess that separate exercises are one instrument.
- Up to four bars fit each row; denser notation expands the logical width
  instead of forcing one ensemble column per page. Attached source-page
  boundaries remain page boundaries. Short-row alignment slots are invisible
  and reject insertion; original stored empty bars remain original bars.
  Clef/key/meter contexts stay independent, and an independent row restates
  its meter when present. No meter is invented for a row that lacks one.
- Touch selection, insertion/drop, drag/reorder, range/issue highlights,
  focus and playback positions translate between display and original cells.
  Next/Previous symbol continue across scanned rows. Page navigation follows
  original selections/playback in the new layout. Structural review previews
  compute their own page grouping, so added bars are not clipped.
- Focused regressions: **14 passed**, covering the real scan, ragged-row
  pixels/hit areas, independent contexts/signatures, source page breaks,
  editing/undo, navigation, playback, thumbnail/PDF consistency and structural
  previews. Editor/PDF captures visually checked in
  `/tmp/note-vision-scanned-layout-qa/`. Analysis clean; **1,045 full-suite
  tests passed**.
- Release **2022** passed Realme RMX1851 / Android 11 QA. Existing NVScan2020
  opened as one page with eight rows of three bars; exported PDF matched.
  Row-two touch selection/focus, E3 → F3 → Undo and original-photo tracking
  worked. Latest user edits were saved before installation; post-install,
  restored and cold-reopen MusicXML exports are byte-identical to that latest
  baseline. All 12 projects retained; NVSymphony2019 keeps its ensemble
  layout. Playback from row two stayed on page 1/1, with an active 44.1 kHz
  stereo track and zero track underruns. Enlarged text (1.8x), landscape and
  app error logs checked. Original font/rotation preferences restored, helper
  removed; saved NVScan2020 left open with playback stopped. No iOS test or
  new subjective listening confirmation. Evidence:
  `/tmp/note-vision-phone-2022/` (including `qa-facts.json`); phone exports:
  `Download/NoteVisionQA2022/`. Tested APK SHA-256:
  `973388b9090f8e93e04be41c223c8b268a1dfcac20591ea9d837b8928a4650ac`.
- MusicXML deliberately retains the stored part structure in this slice;
  flattened/reclassified scan interchange is separate work. Recognition and
  reconstruction errors remain reviewable; detector weights/thresholds are
  unchanged. Automatic instrument/exercise grouping and full parity remain
  on the roadmap.

### Fresh scans of other sheets — 2026-11-05

- Release **2022**, Realme RMX1851 / Android 11: ran three different existing
  handwritten sheet photos through Upload, preprocessing, staff detection,
  on-device inference and reconstruction. This is fresh phone QA, not replay
  of the archived JSON fixtures. No checker fixes were applied.
- `IMG_20261015_211418_667.jpg` → **NVFreshMixed2022**: six visible/detected
  staves, 112 detected symbols, 84 exported notes / six rests, 35 checker
  findings. One editor/PDF page. The source starts in **3/4**, but export
  reads **2/4**; note transcription also differs visibly.
- `IMG_20261015_211453_957.jpg` → **NVFreshPaired2022**: seven visible/detected
  staves, 153 detected symbols, 139 exported notes, 15 checker findings.
  One editor/PDF page. The first bass staff's first source bar has five
  noteheads, but exported P2 bar 1 has one; later bars receive misplaced
  notes. Source braces do not become grand-staff grouping.
- `IMG_20261015_211721_162.jpg` → **NVFreshDense2022**: nine visible/detected
  staves, 225 detected symbols, 172 exported notes / eight rests, 27 checker
  findings. One editor/PDF page. The repeated three-sharp source key becomes
  one/two/three sharps across rows. Stacked source noteheads are not preserved
  as chords (zero MusicXML chord elements); source ties/slurs are also absent.
- All three saved projects survived an app restart (15 total, retaining the
  previous 12). The dense scan cold-opened on page 1/1. Original rotation/font
  preferences restored, temporary helper removed, playback stopped. No app,
  detector or threshold changes. No new listening confirmation or iOS test.
  Evidence: `/tmp/note-vision-fresh-scans-2022/` (`report.json`, source photos,
  scan/editor captures and raw MusicXML/PDF). Phone exports:
  `Download/NoteVisionFreshScans2022/`.
- Follow-up: bar assignment is addressed below; next reproduce meter/key
  recognition against these photos before changing heuristics or thresholds.
  Layout and successful completion do not establish transcription accuracy;
  these existing test
  photos are not an unseen-photo benchmark. Chord/grand-staff reconstruction
  remains part of full parity.

### Guided bar review — 2026-11-05

- Review follows original row/bar reading order and groups related questions.
  Source comparison opens automatically with crop/full-page view and a linked
  symbol outline. The current bar is tappable; pitch and illustrated note-length
  controls, clef, key-signature symbol counts and common meters are available
  directly. Metadata changes are scoped to this staff from the selected bar to
  its next explicit change. Missing notes, barlines and chord repairs still use
  Edit manually with the retained source reference.
- Every nonempty scanned bar receives a setup/photo question, including
  confident detections the rule checker cannot verify. Setup confirmation
  precedes suggested changes, including neighboring bars affected by a move.
  Scanned rows do not borrow clefs/meters from another exercise; no meter is
  inferred from beat totals. Imported/created-score checks retain their
  existing behavior. User-chosen scan lengths may leave an overfull bar while
  corrections continue; timeline validation still runs, and ordinary editor
  length changes retain their existing capacity checks.
- “Review later” defers the whole bar without resolving its questions or
  changing its music. Decisions survive score serialization and Save & close;
  pending bars precede deferred ones, and deferred bars can be resumed. Stable
  target/context fingerprints reopen decisions when relevant music changes.
  Direct corrections use review history, Undo and conflict-checked restore;
  proposed changes remain non-mutating until Apply.
- Batch, overview and History are under More. Phone review has more room and a
  draggable divider; short/enlarged-text layouts scroll the entire panel.
  “Listen to this bar” is bounded to that original bar; proposed listening
  covers the affected bars without unrelated neighbors. End-of-review text
  explicitly notes that the checker can miss wrong notes, bars and chords.
- Automated verification: **1,064 tests passed**, analysis clean. Twelve
  guided-flow widget cases cover photo comparison on phone, small phone,
  enlarged text, landscape and tablet; direct pitch/length/key/meter edits,
  Undo/restore, deferral, save/reopen and bounded listening. Service regressions
  cover setup gating, neighbor changes, serialized deferral and independent
  scan context. Captures checked; release **2023** passed Realme QA below.
  Logs/captures:
  `/tmp/note-vision-guided-review-{analyze,full,targeted,captures}.log`,
  `/tmp/note-vision-guided-review-qa/` and `/tmp/note-vision-phone-2023/`.
  Detector weights/thresholds are unchanged. No claim of complete error
  detection or improved automatic transcription; full parity remains queued.
- Physical **2023** QA: automatic photo/current-bar comparison, crop/full page,
  C5 → D5 → Undo, eighth → half → Undo, key choices/Undo and 2/4 → 3/4 → History
  restore passed on the Realme. Saving the first bar for later and cold restart
  retained **18 pending bars + one deferred**, resuming at Row 1 / Bar 2.
  All **15 projects** retained. The mixed score's restored/cold MusicXML matches
  its baseline byte-for-byte. The user's latest dense-score edits were saved
  and exported before installation; their post-update export is also identical.
  Single-bar listening, 1.8x text and landscape checked; active Android audio
  was 44.1 kHz stereo with zero track underruns. Inspected app logs had no
  Flutter/crash/save errors. Original font/rotation preferences restored,
  temporary helper removed; mixed guided review left open, playback stopped.
  No iOS or new subjective listening test. Evidence:
  `/tmp/note-vision-phone-2023/qa-facts.json`; phone exports:
  `Download/NoteVisionQA2023/`. Tested APK SHA-256:
  `2da9cad49019d7bc30bc43b9b25600581869b94213de4d01ab73e992806c4340`.

### Barline and bar assignment reliability — 2026-11-05

- Reproduced the paired sheet's first bass row: 20 detected notes were split
  **[1, 2, 17]**. Horizontal staff ink promoted a missed note's stem to a
  boundary, while a loose neighboring note box hid a real barline.
- `BarlineFinder` excludes horizontal staff bands from coverage, checks for
  heads attached to otherwise unblocked stems, and traces connected note ink
  inside full symbol boxes. Independent nearby boundaries can survive; weak
  tracing evidence keeps the original conservative box veto. The model,
  detection thresholds, note values and pitch calculations are unchanged.
- Fixed local-runtime replay gives **[3, 8, 9]** and preserves all detected
  symbols in order. Physical release 2024 gives **[3, 9, 8]**, preserving its
  original 139 detected notes exactly; local/phone detections differ slightly
  despite matching the written boundaries. The source first bar contains five
  heads: two remain missed by the model. This improves placement of detected
  music, not complete transcription.
  New scans use the fix; existing saved scores are not reparsed or migrated.
- Three committed native Android picker-prepared JPEGs and frozen detections
  cover **22 staves / 45 visually checked interior boundaries**. Mixed/dense
  score JSON stays identical in replay; all note/rest IDs stay in order.
  Android Bitmap resize (`filter=false`) / JPEG-82 differs from the Dart
  linear-resize approximation in older evaluation tools; the native input
  reproduces the physical paired-sheet failure. These existing practice
  photos are regression cases, not an unseen-photo accuracy benchmark.
- Validation: **83 preprocessing/mapping tests**, **1,070 full-suite tests**,
  analysis clean. Evidence: `/tmp/note-vision-bar-placement-2024/`, including
  failing-before focused regressions, native before/after detection and score
  JSON, and test logs. `tool/barline_trace_test.dart` retains the replay path.
- Physical **2024** QA (Realme RMX1851 / Android 11): freshly uploaded all
  three original photos through the complete on-device pipeline, with no
  review fixes accepted. Saved new projects **NVBarsPaired2024**,
  **NVBarsMixed2024**, **NVBarsDense2024** and exported MusicXML/PDF. Symbol/staff
  counts remain **153/7**, **112/6**, **225/9**. The paired sheet's first
  treble/bass/next-treble rows now split **[5,9,8]**, **[3,9,8]**, **[7,8,9]**.
  All 139 paired-sheet notes keep their pitch/value/order; mixed/dense musical
  MusicXML contents are identical to their original fresh-scan exports.
  All three editor/PDF results remain one page. Existing recognition errors
  (meter/key/chords) remain visible; this is a boundary fix.
- Cold restart retains **18 projects** (all 15 originals plus the three new
  scans); the paired score's cold MusicXML is byte-identical. Existing mixed
  and user-edited dense scores also export byte-identically before/after the
  update. Mixed review retains **18 pending bars + one deferred**, resuming
  at Row 1 / Bar 2. Retained app logs show no Flutter/crash/save errors.
  Font/rotation preferences are unchanged; temporary keyboard/resize helpers
  removed. New paired result left saved and stopped. No iOS or subjective
  listening test. Evidence: `/tmp/note-vision-phone-2024/qa-facts.json`;
  phone exports: `Download/NoteVisionQA2024/`. Tested APK SHA-256:
  `001262beb46fbaf4faf469121cf2e28865db5b560ee1849d72557d36f44a813c`.
- Not yet: recovering missed symbols, reliable meter/key recognition, scan
  chords/grand staves, and ambiguous physically joined note/barline ink.
  Full MuseScore parity remains queued.

### Expanded scan checks — 2026-11-05

- Broadened release **2024** beyond the original three photos with
  `IMG_20261015_211244_372.jpg` (eight sparse exercise staves),
  `IMG_20261015_211332_790.jpg` (eight staves of clef-writing practice),
  `IMG_20261015_211622_458.jpg` (five handwritten song staves with lyrics),
  and `IMG_20261015_211432_497.jpg` (six uneven exercise staves with varied
  keys). These are additional existing dataset photos, not an unseen-model
  benchmark. No production code/model/threshold changes in this QA pass.
- **Regressions in `3e56b39` (fixed by release 2025 below):** replaying identical
  detections through pre-fix/release-2024 geometry loses the sparse sheet's
  row-7 boundary at **x≈353**
  and the uneven sheet's row-4 boundary at **x≈743** (904×1200 prepared input).
  Both are visibly real barlines; the new attached-head check rejects them.
  Candidate coverage remains sufficient. Diagnostic profiles show short
  horizontal ink runs being accepted as attached heads. The uneven sheet's
  row-3 boundary at x≈439.5 improves, but that does not offset these misses.
  The original three-photo pass does not establish broad barline reliability.
- Sparse sheet, physical Realme: **175 symbols / 9 detected staves** against
  eight visible staves. Export has **137 notes / 8 rests**, with seven bars
  allocated to every part; a synthesized staff overlaps real staves near the
  bottom. Initial **4/4 becomes 44/4**, and row keys are inconsistent. The
  missing row-7 boundary is visible in the scan overlay. Saved separately as
  **NVExtraSparse2024**, with MusicXML and one-page PDF. Successful completion
  and one-page layout do not mean correct transcription.
- Clef-writing negative control, physical Realme: **121 symbols / 8 staves**;
  **zero notes and rests** in exported MusicXML. Playback, notation review and
  PDF export are disabled as expected for this empty musical score. Saved
  separately as **NVExtraClefs2024**; the QA export guard correctly stopped
  instead of pressing disabled PDF export.
- Song, physical Realme: **117 symbols / 5 staves**, **92 notes / 10 rests**.
  Both real barlines in row 2 are absent in the overlay; beat fallback makes
  seven bars, then every part is padded to seven. This row also has no
  boundaries with the old geometry in the fixed-detection replay, so it is
  an existing failure rather than a new regression. Saved/exported separately
  as **NVExtraSong2024**. Chord names/lyrics are not reconstructed; some chord
  text is detected as accidentals. The PDF is one page with many empty bars.
- Uneven exercises, physical Realme: **133 symbols / 6 staves**, **96 notes /
  zero rests** despite visible filled-rectangle rest marks. The row-4 x≈743
  barline is missing in the phone overlay. Rows without detected boundaries
  use beat fallback; row 5 becomes 21 bars and every part is padded to 21.
  Saved/exported separately as **NVExtraRagged2024**. One-page editor/PDF output
  compresses excessive empty bars into very small notation; layout completion
  is not an accuracy or readability pass.
- Save/export completed for all four as separate projects (three PDFs; clef-only
  PDF correctly disabled). Cold restart retains **22 projects**, including all
  18 originals; the uneven score's cold MusicXML is byte-identical. The paired
  score open before this QA also exports byte-identically and was restored,
  saved and stopped. Retained app logs have no Flutter/crash/save errors.
  Original automatic rotation/font settings restored; temporary helpers removed.
  Exports and source photos: `Download/NoteVisionQAExtra2024/` (photos in
  `Photos/`). Facts/hashes: `/tmp/note-vision-extra-images-2024/qa-facts.json`.
  No iOS/listening test or new build; the unchanged app's prior 1,070-test pass
  does not cover these manual accuracy failures.
- Next: fix the attached-head false veto and add both real-photo regressions
  before proceeding with meter/key reconstruction. Also reproduce duplicate
  synthesized staves and beat-count fallback/padded bars on these sheets.
  Full parity remains queued. Evidence: `/tmp/note-vision-extra-images-2024/`
  (native-prepared inputs, fixed raw detections, geometry comparison, candidate
  diagnostics and phone scan/export captures).

### Barline false-head follow-up — 2026-11-06

- The expanded QA failures are now committed regression inputs. A candidate
  stem must have consecutive broad ink rows spanning at least a third of a
  staff space, with a peak width over half a space and the existing stroke
  guards. This replaces the scale-independent three-row veto. A small staff
  fragment or neighboring head edge no longer hides a real line; a tapered
  head can still qualify without being wide on every row.
- Frozen-input tests restore sparse row 7 at **x≈353** and uneven row 4 at
  **x≈743**. Every detected note/rest ID remains in reading order. Original
  three-photo expectations, including rejection of the paired sheet's missed
  note stem at x≈241, remain intact. Song and clef-only score JSON stays
  identical to its frozen baseline. All seven prepared photos are committed;
  the four expanded baselines retain known recognition errors and are not
  complete transcription ground truth.
- Two real-photo cases and two scaled ink-fragment tests fail with the prior
  finder and pass with the updated shape check. A larger missed-head case
  keeps stem rejection covered. Focused tests: **16 passed**; full suite:
  **1,077 passed**, analysis clean.
  Logs: `/tmp/note-vision-barline-regressions-2025/` (including isolated
  previous-finder replay in `before-final.log`).
- Remaining: duplicate synthesized staff, 4/4 → 44/4, missed song boundaries
  and rests, and beat-count fallback/padded bars still need separate fixes.
  Model weights, confidence thresholds and score migration are unchanged;
  existing projects are not reparsed. Full MuseScore parity remains queued.
- Release **2025**, Realme RMX1851 / Android 11: fresh sparse-sheet Upload
  restores the row-7 boundary in the overlay and saved MusicXML. Detected-note
  distribution changes **[14,5] → [6,8,5]** (trailing padded bars omitted).
  All **137 notes / 8 rests** retain their exact exported contents and order;
  other row assignments are unchanged. Saved as **NVLinesSparse2025**, with
  MusicXML/PDF. The extra staff, 44/4 and padded bars remain visible.
- Fresh uneven-sheet Upload restores row 4 at x≈743 in the phone overlay;
  saved MusicXML changes **[2,4,9] → [2,4,8,1]** with all **96 notes** retaining
  exact contents/order, and other row assignments unchanged. Saved as
  **NVLinesRagged2025**, with MusicXML/PDF. Local-runtime frozen detections give
  [2,4,7,1] instead; as before, local/phone note counts are not interchangeable.
  Existing missed rests and 21-bar padding remain separate failures.
- Fresh paired-sheet control still has **153 symbols / 7 staves**, with all
  **139 notes** and their exported contents/order unchanged from release 2024.
  First bass row remains **[3,9,8]**; the missed stem does not return as a false
  boundary. Saved/exported as **NVLinesPaired2025**. Two missing source notes
  remain missed by the unchanged model.
- All three MusicXML/PDF exports completed; PDFs remain one page (padded-case
  readability problems are unchanged). Cold restart retains **25 projects**,
  including all 22 originals. Sparse/uneven cold exports are byte-identical;
  the originally open **NVBarsPaired2024** also exports byte-identically before
  and after the update. Original score restored, saved and stopped. Retained
  app logs have no Flutter/crash/save errors. Original font/rotation settings
  restored; temporary helper/photo copies removed. No iOS or new subjective
  listening test. Evidence: `/tmp/note-vision-barline-regressions-2025/qa-facts.json`;
  phone exports: `Download/NoteVisionQA2025/`. Tested APK SHA-256:
  `5e042523699d1997d1f547681a34b2920b4d1526a49641b0578eb9e6174b2473`.

### Aligned meter reconstruction — 2026-11-06

- Reproduced the sparse photo's 44/4: a high-confidence false `timeSig4` near
  the key and the real upper 4 were both concatenated above the lower 4.
  `SignatureInferrer` now builds contiguous, non-overlapping digit runs and
  selects a centered upper/lower stack using glyph geometry and staff slope.
  Confidence and beat totals do not select the meter. Overlapping alternatives
  cannot become adjacent digits; comparable conflicting stacks return no
  inferred meter with a warning. Extra/repeated digits also produce a warning.
- Multi-digit numerators/denominators remain supported, including a genuinely
  centered 44/4; this is not a numeric cap or a replacement of every 44.
  Explicit C/cut-time signs retain their behavior. Missing rows and zero
  components remain unresolved. No neighboring exercise supplies missing meter.
- **24 focused tests passed**: 17 geometry cases and seven frozen-photo
  pipeline cases. Nine unit cases and the sparse-photo case fail with the
  previous parser. Exact before/after score-JSON replay changes only three
  inherited numerator fields **44 → 4** in sparse P1; all notes, rests, keys,
  bars and the other six scores are identical. These frozen inputs retain
  known detector errors and are not complete musical ground truth.
- Full suite: **1,101 tests passed**, analysis clean. Only the three touched
  Dart files were formatted. The seven-photo replay and before-failure logs
  are retained with the focused/full logs.
- Model assets/confidence cutoffs, staff assignment, key inference, beat-count
  fallback and existing project files are unchanged. Remaining extra staff,
  misclassified/missing symbols (including mixed 3/4 → 2/4), song boundaries,
  padded bars and full parity stay queued.
  Evidence: `/tmp/note-vision-meter-2026/` (including `score-differences.json`,
  before/focused logs and the seven before/after score replays).
- Physical **2026** QA, Realme RMX1851 / Android 11: fresh Upload of the
  sparse sheet retains **175 symbols / 9 staves**, **137 notes / 8 rests**.
  Saved as **NVMeterSparse2026**, with MusicXML/PDF. All three inherited
  P1 meters now export **4/4**, and the rendered PDF shows 4/4. Compared with
  release 2025, only those numerator fields change; musical XML otherwise
  matches exactly, including notes/rests, keys and bar assignments. The raw
  overlay still includes the false detected digit, and the extra staff and
  padded bars remain known failures.
- Fresh uneven-sheet control retains **133 symbols / 6 staves**, **96 notes**,
  and its existing 4/4 and 2/4 meters. Saved/exported as **NVMeterRagged2026**;
  musical XML is identical to release 2025. Its zero-rest recognition error,
  missed boundaries and 21-bar padding remain; PDF export is still one page.
- Cold restart retains **27 projects**, including all 25 originals. Corrected
  sparse MusicXML is byte-identical after reopening. The originally open
  **NVBarsPaired2024** also exports byte-identically before/after installation;
  it was restored, saved and stopped. Retained logs show no Flutter/crash/save
  errors. Original phone preferences restored and temporary helpers/photo
  copies removed. No iOS or subjective listening test. Facts/hashes:
  `/tmp/note-vision-meter-2026/qa-facts.json`; phone exports:
  `Download/NoteVisionQA2026/`. Tested APK SHA-256:
  `281918ac8cf18f863722eb08e0ce02e3340bd0b1403a2de7cf645b1a5f732f87`.

### Traced staff recovery and natural scan bars — 2026-11-06

- Sparse's giant G-clef box covers two real traced rows, but its center lies
  between them at the left edge. Clef fallback now recognizes those two staff
  middles at the box's own x, using their slope offsets, and adds no ninth row.
  Already synthesized rows also cover repeated clef detections on the same row.
  A lone untraced clef still recovers a staff from the existing proportions.
- `ScoreBuilder` no longer pads scanned parts to the longest row. The existing
  reading-order projection already supports ragged parts and hidden display-only
  cells. Real empty measures and all measures in a longer lower row are retained.
  Existing saved scores are not reparsed or automatically trimmed; imported
  ensembles/templates do not use this scan builder.
- Frozen full-output replay of all seven photos preserves every note/rest ID,
  order and duration. Sparse changes **9 → 8** staves and **63 → 24** stored bars
  (eight rows of three). Ten bottom-row pitch steps now use the actual traced
  staff instead of the giant fake staff. The other six photos' musical symbols
  are identical: uneven bars **[21,21,21,21,21,21] → [2,2,3,4,21,5]**,
  song **[7,7,7,7,7] → [3,7,3,3,3]**, mixed
  **[4,4,4,4,4,4] → [4,3,3,3,3,3]**; bass, dense and clef-only unchanged.
- Three new staff cases reproduce the bug via public post-inference decoding,
  including the sparse native-prepared photo's frozen clef boxes. They and the
  updated padding expectation fail before the fix. Another test retains a real
  empty middle bar and all bars of a longer lower row. Full **1,105 tests passed**;
  `flutter analyze` clean. Existing ragged-row editor/PDF/hit-target tests pass.
- Model/confidence thresholds, inferred note values, key inference and beat-count
  fallback are unchanged. Missing/misclassified notes/rests, wrong meter digits,
  song boundaries and the uneven row's unresolved 21-bar fallback still need
  work; full MuseScore parity remains queued. Baselines are regression controls,
  not complete musical ground truth. Evidence:
  `/tmp/note-vision-staves-2027/`, including before-failure logs and
  `score-differences.json`.
- QA photo staging: `tool/android_qa_images.py` copies selected dataset files to
  `Pictures/NoteVisionQA`, verifies SHA-256, updates only the copies' timestamps
  and finishes MediaStore indexing. An adb-pushed pending image is otherwise
  hidden from the picker; modifying the EXIF-derived MediaStore capture-date
  column is not reliable once published. Dataset originals have no EXIF capture
  dates, so refreshed file dates put all three selected photos at the top of
  Android Photos → Recent. Verified visually in source order: sparse, uneven,
  then new `IMG_20261017_160726_522` (five-staff control). Originals stay intact;
  the named album is retained for future QA. Embedded older dates cause a clear
  helper failure instead of an unsupported claim that the photo is recent.
- Physical **2027** QA, Realme RMX1851 / Android 11: sparse retains
  **175 symbols**, **137 notes / 8 rests**, now **8 staves** and eight rows of
  three bars (**24**, previously 63). Saved **NVStaffSparse2027**; MusicXML
  confirms ten bottom-row pitch changes (including the B-flat implied by its
  key) and unchanged other note content/order. PDF is one page with eight
  populated rows and no fake ninth row or trailing padded bars.
- Uneven retains **133 symbols / 6 staves / 96 notes / 0 detected rests**,
  stored counts **[2,2,3,4,21,5]** (**37**, previously 126). Saved
  **NVStaffRagged2027**; all exported note content/order matches release 2026.
  PDF is one page with twelve visual rows; the unresolved 21-bar fallback
  still takes six rows, but other rows have no trailing musical bars. Seeking
  reaches **37/37, Staff 6 measure 5**; playback from the beginning shows Pause
  and Stop returns to Play. This checks transport, not subjective audio.
- New dataset control `IMG_20261017_160726_522` scans as **113 symbols /
  5 staves**, saved **NVStaffControl2027** with five rows of three bars, **44
  notes / 16 rests**, and one-page PDF/MusicXML. This checks the scan/export
  path on another photo, not complete pitch/rhythm/meter accuracy. All three
  new scores reopen after a cold restart with byte-identical MusicXML; the
  collection now shows **30 projects** (27 before these three scans).
- The originally open **NVBarsPaired2024** exports byte-identically before
  installation and after cold reopening; restored saved and stopped. Original
  font/rotation preferences restored. Retained app logs contain **62 app lines /
  zero Flutter/crash/save errors**. Temporary keyboard/UI-dump helpers removed;
  the requested three recent photo copies remain in `Pictures/NoteVisionQA`.
  Final helper rerun succeeds and preserves source image bytes. QA exports are
  retained in `Download/NoteVisionQA2027/`; facts/hashes are in
  `/tmp/note-vision-staves-2027/qa-facts.json`. Tested APK SHA-256:
  `066cd85827da6197053fcf7c2f5ad8578ce670ef9850fd541fbaca8b98682385`.

### Unresolved rows instead of guessed bars — 2026-11-06

- Visual inspection confirms that the uneven sheet's fifth and sixth rows
  have no drawn internal barlines. Beat-count fallback fabricated **21** and
  **5** bars from their notes. A meter alone does not establish boundaries.
  No-barline rows now remain complete with `Measure.unresolvedBarlines`;
  rows with detected boundaries retain their existing grouping.
- The flag survives `copyWith`, score/project JSON and undo; old JSON defaults
  false and is not migrated. Review asks the user to compare the whole row,
  distinguishes possible unbarred exercises from missed lines, and offers no
  automatic beat-count split. The existing Keep/Review later decisions work.
  Ordinary MusicXML preserves the complete row in one measure with its meter;
  this format does not carry NoteVision's unresolved-boundary review flag.
- Each unresolved row spans all display columns. Hidden layout cells remain
  absent from saved music. Canvas/PDF do not draw invented bar numbers or end
  strokes, and share full-width note placement with hit/input targets and the
  playhead. Review focus includes the row's far end. Note entry and duration
  correction do not force music into invented bars; normal meter-aware input
  and its overflow behavior are retained for confirmed bars.
- Four new reconstruction/review regressions fail before the change. They
  cover explicit note values, the native-prepared uneven photo, persistent
  flag/copy behavior and a review warning without a guessed split. Layout
  checks cover full-width placement/PDF, far-end selection/edit/undo, review
  messaging/focus and insertion. Two input cases cover appending and changing
  duration on an overfull unresolved row while preserving the rest and undo.
- Seven frozen full-output replays preserve every note/rest JSON exactly.
  Uneven **[2,2,3,4,21,5] → [2,2,3,4,1,1]**, song
  **[3,7,3,3,3] → [3,1,3,3,3]**. Both now contain 13 stored groups, including
  unresolved rows; these are not 13 verified written bars. Sparse, bass,
  mixed, dense and clef-only entire scores are identical to release 2027.
- The song's missed true barlines are diagnosed, not fixed in this slice.
  Its second staff trace ends near x266 and restricts the current search to
  x311. A diagnostic wider search finds the x343 line, but the x612 line
  still fails the above-staff check because the extrapolated top drifts.
  This needs a geometry fix with stem controls. Finder logic, frozen model,
  confidence cutoffs and detected note values are unchanged. Full parity and
  remaining recognition errors stay queued. Evidence:
  Full **1,115 tests passed**, analysis clean; **38 input/layout tests passed**.
  `/tmp/note-vision-boundaries-2028/`, including before-failure logs,
  `diagnosis{,-fullwidth}.log` and `replay-comparison.json`.
- Physical **2028** QA, Realme RMX1851 / Android 11: fresh uneven Upload
  retains **133 symbols / 6 staves / 96 notes / 0 detected rests**. Saved
  **NVRowsRagged2028** with counts **[2,2,3,4,1,1]**. Exported MusicXML
  preserves every note's pitch, accidental, duration and other content/order
  against release 2027. One-page PDF now shows **six** source rows instead of
  twelve; the last two span the full row with no invented bar numbers/strokes.
  Cold reopen retains the metadata: Review reaches **Row 5 · Barlines
  unconfirmed**, and its scrollable details show the explicit explanation
  without an automatic split. Source photo remains available. Scroll within
  the details above the fixed footer to reach the explanation below the
  signature controls. Evidence: `phone/review-verification.json`
  and `boundary-warning-final2028.png` in the work directory.
- The uneven row's **12/13, Staff 5 measure 1** position supports Play/Stop
  after reopening. New song Upload retains **117 symbols / 5 staves / 92
  notes / 10 rests** (phone counts differ from frozen local inference's 12
  rests). Saved **NVRowsSong2028**, with groups **[3,1,3,3,3]** and all note/rest
  pitches, values and other content/order matching its physical release-2024
  baseline. Explicit beam begin/end tags can change when guessed bars disappear.
  PDF has five source rows on one page. Row 2 remains unconfirmed: its real
  boundaries and other recognition mistakes still require review.
- Fresh sparse control retains **175 symbols / 8 staves / 137 notes / 8
  rests** and eight rows of three bars, saved **NVRowsSparse2028**. MusicXML
  is byte-identical to release 2027; its one-page PDF raster is pixel-identical
  at 1400 px. The new policy does not alter confirmed rows. QA selected uneven
  and song via recent copies **NVQA2028-01/02** in `Pictures/NoteVisionQA`, plus
  the retained sparse copy from batch 2027. Originals are unchanged.
- Final cold restart shows **33 projects** (30 before the three new scans).
  All three new scores' cold MusicXML exports are byte-identical to their
  initial exports, including the unresolved rows. The separate earlier
  cold-reopen review check confirms the unresolved flag itself is preserved.
- The originally open **NVBarsPaired2024** exports byte-identically before
  installation and after cold reopen; restored saved and stopped. Original
  phone preferences restored; temporary keyboard/UI-dump helpers removed.
  Retained logs contain **45 app lines / zero Flutter/crash/save errors**.
  Test-photo copies remain recent in `Pictures/NoteVisionQA`; originals are
  unchanged. Exports: `Download/NoteVisionQA2028/`; facts/hashes:
  `/tmp/note-vision-boundaries-2028/qa-facts.json`. Tested APK SHA-256:
  `0ac26d61ed193120c766628681deb2eea9ea937761bd6d60a64c2b018a2ba0a7`.

### Shifted staff runs and the song's barlines — 2026-11-07

- The song's second clef chose a false short candidate: **four real staff
  tracks plus a ledger line**, shifted down by one line. Its clef-fit cost
  (~0.45) beat the real longer candidate (~0.64), despite only ten observed
  strips versus seventeen. The short trace ended near x266 and excluded the
  true boundaries from the barline search.
- `StaffLineTracer` carries per-line track identity through joined fragments.
  Competing eligible five-line runs sharing four ordered tracks at a one-line
  shift cannot represent distinct staves; prefer the run supported by more
  independent strips. Equal support keeps the previous clef choice. The
  existing oversized-staff rejection runs before this comparison, so rejected
  geometry cannot suppress a valid staff. Independent short staves remain.
- The real second-row trace reaches x654. The unchanged `BarlineFinder` now
  finds both written lines at x≈342/611 (reference x≈343/612), with no relaxed
  cover, width, head or extension checks. The x241 note stem remains rejected,
  including after removing the nearby note detections. Frozen model weights,
  detector confidence cutoffs and clef-fit thresholds are unchanged.
- Two initial cases reproduce the old failure. Four new tests cover missing
  top/bottom tracks with competing ledger runs, a true shorter staff with
  independent tracks, and the native-prepared song image through tracing,
  barline finding and reconstruction. The first row-2 ledger note maps to
  **C4**, as written, instead of E4; all non-pitch symbol fields remain equal.
- Seven frozen full-output replays preserve every note/rest ID, reading order
  and length. Song groups **[3,1,3,3,3] → [3,3,3,3,3]** (15 bars), and **31**
  second-row note pitches use the corrected staff geometry. Every other
  musical symbol field is identical, including confidence, source bounds,
  note values and chord flags. The six other complete scores (sparse, uneven,
  bass, mixed, dense, clef-only) are identical to release 2028. Existing saved
  scores are not migrated or rescanned. Remaining head localization and
  recognition errors still require review; full MuseScore parity remains
  queued. Full **1,119 tests passed**; analysis clean. Evidence:
  `/tmp/note-vision-trace-2029/`, including before logs, candidate diagnostics,
  final four-case test log, and `comparison.json`.
- Realme release **2029**: refreshed, checksum-verified dataset copies appear
  first in the photo picker. Fresh song/sparse/uneven scans detect
  **117/175/133 symbols**, **5/8/6 staves**. Song exports **15 bars**, **92
  notes/10 rests**, with all lengths and order unchanged and no changes in
  other rows. The native second-row output has **32** geometry-derived pitch
  changes (local frozen replay: 31); first ledger note is C4. Sparse and uneven
  MusicXML scores and PDF rasters are identical to release 2028, preserving
  **24 bars/137 notes/8 rests** and **13 groups/96 notes/0 rests** respectively.
  All PDFs are one page. Play/Stop works on the corrected second row;
  subjective listening was not performed.
- After app restart, all three new projects export byte-identically. The
  pre-existing `NVRowsSong2028` also matches its pre-install export exactly,
  preserving its unresolved row; no saved-project reparse. Collection
  **33 → 36**. Retained logs contain **66 app lines**, with no Flutter,
  crash or save errors. Tested APK SHA-256:
  `201f9be91652ba7535bbf071c2a026f3df6920abbd960367d97215bfd11a3b88`.
- Original font/rotation preferences and Home/collection state restored;
  temporary helpers removed, recent test copies retained. Eleven exports
  archived and checksum-verified in `Download/NoteVisionQA2029/`. Complete
  evidence: `/tmp/note-vision-trace-2029/qa-facts.json`. Remaining recognition
  errors and full MuseScore parity stay queued.

### Beam-guided pitch heads — 2026-11-07

- The end-band ink heuristic can choose a dark beam instead of the notehead,
  causing large pitch errors. Use the existing detected beam rectangles on
  quarter boxes already interpreted as beamed eighths/sixteenths: a beam
  touching only one end band selects the opposite end for pitch. Reuse the
  existing band proportions and stem-tip reach; no model, confidence, beam
  matching or suppression threshold changes.
- Suppression runs on the original head estimates. The surviving symbol keeps
  its box and receives separate `pitchBox` metadata via `copyWith`. Only
  `PitchCalculator` reads it; staff ownership, note order, dot/accidental
  association and source bounds retain their prior geometry. Directly moving
  the shared box was rejected after replay showed ledger notes changing staff
  and a dot changing note length. Existing projects are not rescanned.
- Absent, unrelated, middle-band and both-end beams retain the ink fallback.
  Explicit eighth/sixteenth, half and whole model classes are unchanged.
  Seventeen tests cover both stem directions, these fallbacks, short stems,
  class isolation, public decoding through pitch/JSON, and **43 visually
  checked head ends across four photos**. Disabling beam guidance reproduces
  eight failures. The real-photo fixture adds beam rectangles and head-end
  labels; historical detection JSON is not rewritten.
- All seven full frozen-output replays preserve every detected symbol, note
  count/order/value, source bound, staff and barline. Only pitch step/octave
  changes: **song 25, dense 10, paired 7, sparse 1**. Uneven, mixed and clef-only
  complete scores are identical. Full **1,136 tests passed**, analysis clean.
  Evidence: `/tmp/note-vision-heads-2030/`, including `before-guide.log`,
  visual crop comparisons, seven-photo `comparison.json` and complete logs.
- Remaining: fixed-band centering still misses exact head contours; explicit
  flagged notes and wrongly detected beams can remain wrong. These existing
  dataset photos are regression examples, not a broad accuracy benchmark.
  Missing/misclassified symbols and full MuseScore parity stay queued.
- Realme release **2030**: fresh song/dense/paired scans detect
  **117/225/153 symbols**, **5/9/7 staves**. Exported pitch changes are
  **25/9/7** respectively (dense local replay: 10). Every non-pitch note
  field, note/rest count, bar assignment, key and meter declaration matches
  the native baseline. Song has **92 notes/10 rests/15 bars**; dense
  **172/8/27**; paired **139/0/21**. All three one-page PDFs are visually
  checked. Song second-row Play/Stop passed; no subjective listening test.
- The re-encoded dense dataset variant produced **230 symbols**, so the QA
  guard stopped before saving or comparing it to the original baseline.
  Recent original-pixel dense/paired copies change EXIF date text only:
  compressed JPEG data, decoded pixels, orientation and source originals
  are checksum-verified unchanged. This avoids treating a new image encoding
  as an app regression. Equal capture timestamps reordered the thumbnails;
  verify the source preview. Evidence: `phone/recent-pixel-copies.json`.
- Cold restart: all three new projects export byte-identically; the older
  `NVTraceSong2029` matches its pre-install export exactly. Collection
  **36 → 39**. Retained logs have **37 app lines**, no Flutter/crash/save
  errors. Original font/rotation preferences and Home/collection state are
  restored; temporary helpers removed, requested photo copies retained.
  Eleven exports and two original-byte input copies are archived and hashed
  in `Download/NoteVisionQA2030/`. Complete evidence:
  `/tmp/note-vision-heads-2030/qa-facts.json`. Tested APK SHA-256:
  `04a3c16005dda1af860ca2a827c841566351c0d88e405f3eb1c883f29e815cbb`.
  Exact head centering, other symbol errors and full MuseScore parity remain
  queued.

### Bounded head centering — 2026-11-07

- `NoteheadCenterFinder` may refine the vertical centre of a one-ended beamed
  pitch estimate. Local paper contrast and solid-window support filter thin
  strokes. A single compact component must be fully bounded, have supported
  middle and no enclosed light pockets. Hollow, competing, clipped, tiny,
  low-contrast or ambiguous-beam evidence keeps the previous estimate. Binary
  and 8-bit luminance share a normalized scale. Only `pitchBox` changes;
  association geometry, source review, NMS and detector cutoffs stay fixed.
- **21 new tests** cover two scales/directions, thin/thick strokes, hollow and
  weak ink, clipping/invalid inputs, competing blobs, class/beam isolation,
  decoder/pitch/JSON integration and six real-photo cases. Three photo intervals
  improve; three known offset heads deliberately retain their estimates when
  fitting evidence is insufficient. Ten tests fail with fitting disabled.
  Full **1,157 tests passed**; analysis clean.
- Seven fixed-output photo replays change **11 pitch-centre coordinates**.
  Only two score pitches change: song row 3/bar 2 and dense row 9/bar 3,
  **A4 → B4**. Every note/rest ID, order, length, source bound, key/meter,
  staff and barline is preserved; all other score fields are identical.
  Sparse, uneven, paired, mixed and clef-only complete scores are unchanged.
- Reproducible production Dart diagnostic:
  `NV_CENTER_MPP=<annotations/images root> NV_CENTER_WORK=<out> flutter test
  --no-pub tool/notehead_center_eval_test.dart`. **11,864** beamed filled-head
  annotations on unshared stems supply whole-symbol boxes and known head ends;
  **1,700** qualify. Mean absolute vertical error in head-height units changes
  **0.1831 → 0.1590** overall, **0.2193 → 0.0513** on fits. **1,436** improve,
  **252** worsen and **12** tie; **seven** worsen by over a quarter head height.
  Both writer subsets improve on average. This uses known annotation boxes,
  not inference or an unseen-model musical-accuracy benchmark. Thick staff/
  ledger intersections and steep/slanted heads remain counterexamples.
- Evidence: `/tmp/note-vision-centers-2031/`, including before/focused/full
  logs, seven-photo `comparison.json`, photo crops, annotation summaries and
  the largest regression examples. Remaining shape/symbol errors and full
  MuseScore parity stay queued.
- Realme release **2031**: original-pixel song/dense/paired copies are placed
  first in the gallery using staggered copy dates, preserving source originals,
  compressed JPEG data and orientation. **117/225/153 symbols**, **5/9/7 staves**.
  Native song and dense each confirm the same single **A4 → B4**; every other
  note field, count/order, key/meter and bar placement is preserved. Song has
  **92 notes/10 rests/15 bars**, dense **172/8/27**, paired **139/0/21**.
  Paired MusicXML is byte-identical and its PDF raster pixel-identical to 2030.
  All PDFs are one page; song/dense renders visually checked. Play/Stop passes;
  subjective listening was not performed.
- All three new projects cold-reopen with byte-identical exports. Existing
  `NVHeadsSong2030` matches its pre-install export exactly. Collection
  **39 → 42**. **50** retained app log lines contain no Flutter/crash/save
  errors. Original font/rotation preferences and Home/collection state are
  restored; temporary helpers removed, requested recent copies retained.
  Eleven exports archived/checksummed in `Download/NoteVisionQA2031/`.
  Complete evidence: `/tmp/note-vision-centers-2031/qa-facts.json`.
  Tested APK SHA-256:
  `2c3d46979cd372ace2b1dda3525e257d98cfa54bfdb9e895619a54a1f6f55f1f`.

### Key-signature model/reconstruction diagnosis — 2026-11-08

- Visually checked **27 written sharp glyphs**, three per row, on the dense
  sheet. Historical detections and current production decoding of its frozen
  local raw outputs give leading counts **1,2,2,3,2,1,3,3,3**; the mapper
  counts exactly those symbols. Six missing glyphs have peak sharp scores
  **0.171/0.228/0.355/0.283/0.294/0.394**, below the frozen **0.40** cutoff.
  One is classified as `timeSig4` at **0.668** (peak sharp **0.013**).
  Under the local matching rules, none has an above-cutoff winning sharp
  candidate lost to NMS, staff assignment or leading-signature collection.
- The diagnostic counterfactual supplies only the manually labelled sharp
  glyphs. All nine rows then map three sharps, with every mapped note/rest
  unchanged. `tool/key_signature_trace_test.dart` runs on the existing fixture;
  `NV_KEY_WORK=<full/raw root>` additionally invokes the actual decoder.
  `NV_KEY_REPORT=<output.json>` saves per-glyph details;
  `NV_KEY_LABELS=<B9 24-class YOLO label file>` audits existing annotations.
  `test/fixtures/barlines/key_sharp_centers.json` records approximate matching
  centers, not exact contours, key-pitch semantics or a complete transcription.
- The final B9 dataset puts this page in **test**, with all 27 key glyphs
  already labelled as sharp (29 sharp labels including body accidentals).
  The incoming Roboflow archive uses a different class order/split; do not
  mistake that archive's `train` location for the final training split.
  Keep test membership intact. Next model work should first audit separate
  validation pages, then use independent training examples for weak sharps
  and sharp/digit confusion. Any cutoff change still requires validation.
- This diagnoses a known photo, not unseen recognition accuracy or proof
  that all key-signature mapping is correct. Production code, model, cutoffs,
  saved projects, phone installation and dataset originals remain unchanged.
  No new phone QA is needed for this diagnostic-only change. Full parity
  and other everyday recognition work remain queued. Evidence:
  `/tmp/note-vision-key-triage-2031/` (frozen/raw reports and annotation audit).
- Final validation: fixture diagnostic passed; raw decoder/annotation audit
  passed; `flutter analyze --no-pub` clean; full **1,157 tests passed**;
  `git diff --check` clean. Initial checks exhausted `/tmp` quota; only this
  turn's failed compiler caches were removed, and verification reran with
  temporary files under the ignored project build cache.

### Correct opening keys across selected scan rows — 2026-11-08

- Review's bar setup now offers **Correct key across rows**. Choose the correct
  sharp/flat count and rows, then preview before applying. Only the current row
  starts selected; Select all and Clear selection are explicit. Current/Proposed
  notation and the focused row's photo are shown before the affected-bar list;
  the preview-row selector changes both views. Back/Cancel/preview do not edit.
- `ScanKeyCorrection` changes opening keys, including repeated values stored
  by the scan mapper, up to the next different key on each chosen row. An
  explicit zero-sharp key is a boundary. Inherited null values remain inherited.
  Already matching rows are skipped. No note/accidental, rhythm, clef, meter,
  barline or source evidence is rewritten. Playback and XML naturally follow
  the corrected key; written naturals remain explicit naturals.
- One application follows the existing review-history/Undo/Redo/save/restore
  path across all affected rows. Playback beginning during preview blocks the
  correction; a stale score cannot accept its plan. The flow is limited to
  independent sequential scans, excluding imported/ensemble, linked/TAB and
  percussion notation. Full parity and automatic recognition work remain queued.
- Regression coverage includes the dense nine-row photo: correcting five
  incomplete opening keys makes all nine keys three sharps, with all other
  score fields unchanged. Additional checks cover later key changes, missing
  keys, no-op/invalid/stale plans, excluded score types, history restore and
  JSON persistence, Undo/Redo, playback/XML naturals, explicit row selection,
  Cancel/preview, playback locking and small/large-text/landscape layouts.
  Evidence: `/tmp/note-vision-key-rows-2032/`.
- Automated validation: **13 new tests**, full **1,170 passed**; analysis clean;
  focused new/previous guided-review checks passed. Small-phone, enlarged-text,
  landscape and tablet preview captures were visually inspected. UI tests load
  shipped fonts consistently in screenshot and ordinary runs; their lazy-list
  navigation explicitly scrolls controls into view.
- Scope: opening sections only. Later different contexts stay even if they
  also need correction. The native dense scan retains its existing -1 keys
  on row 1/bar 3 and row 2/bars 2–3; this feature does not certify those as
  musical key changes. Separating body accidentals at bar openings from key
  changes is addressed for clear continuation cases below; ambiguous cases
  and model recognition remain.
- **Realme release 2032 passed:** saved `NVCenterDense2031` matches its fresh
  baseline after installation. Default selection, Cancel, Current/Proposed and
  row/photo following verified. A single-row edit changes two keys. Batch
  selection changes **12 key entries in five rows**, skipping four matching
  rows and preserving later different contexts. All **172 written notes / eight
  rests** retain their fields; **14 sounding alterations** follow the corrected
  key with written natural/carry behavior verified. One Undo restores baseline,
  one Redo reproduces the batch. Corrected cold reopen is byte-identical; saved
  History restores the original and a second cold reopen exactly matches its
  pre-install baseline. PDF is one page and visually checked; Play/Stop,
  enlarged text (1.8x) and landscape checked. No subjective listening claim.
- All **42 projects** retained. Original font/rotation and Home restored;
  temporary helpers removed. Eleven exports archived/checksummed in
  `Download/NoteVisionQA2032/`. **386 retained app log lines** have no
  Flutter/crash/save errors. No detector/model/cutoff changes or fresh inference.
  Complete facts: `/tmp/note-vision-key-rows-2032/phone/qa-facts.json`.
  Tested APK SHA-256:
  `d383b684c0e09c203b0e3fd2d8dfaebf96aea4a8fa891ce1029763bd8063617d`.

### Note-attached accidentals at continuation-bar openings — 2026-11-08

- Confirmed against source crops: dense row 1/bar 3's C-flat, dense row 2/bar
  2's F-flat and sparse row 1/bar 3's E-flat belong to individual first notes.
  The old leading-region collector consumed them as key glyphs. The dense
  false key persisted into later bars; sparse's false -1 happened to equal its
  opening key, but its written E-flat was still lost.
- `SignatureInferrer.leadingNoteAccidental` separates a single, tightly
  aligned glyph on a unique first-onset note in a continuation bar without
  a clef/time anchor. Staff-scale gap/vertical support follows slope and
  allows limited loose-box overlap. Existing pitch spelling retains ambiguous
  F-sharp/B-flat key positions and F/B-natural cancellations. First rows,
  groups, anchors, first rests, competing heads, unsupported clefs and weak
  geometry retain their old reading. This is deliberately not general key
  recognition or a policy that forbids mid-piece key changes.
- The paired glyph is consumed exactly once, preserving the first note's
  written accidental without assigning the same loose box to its next note.
  Inherited keys, accidental carry, next-bar reset, playback and XML follow
  the existing notation rules. Detector output, cutoffs, staff/barline/source
  geometry, note steps/octaves, counts/order and rhythms are unchanged.
- **27 new tests** cover three scales and slopes, treble/bass, genuine and
  ambiguous keys/cancellations, contexts and geometry fallbacks, JSON/XML,
  playback carry/reset and the two photos. Disabling the new rule fails
  **12 tests**. Full **1,197 passed**; analysis clean; diff check clean.
- Seven fixed-detection replay audit: only **three written flats** and **three
  dense key contexts** change (-1 → 1 on row 1/bar 3; -1 → 2 on row 2/bars
  2–3). Sparse's key remains its original -1. Mixed, paired, uneven, song and
  clef-only complete scores are identical. This is known-photo evidence,
  not unseen-model or full musical-transcription accuracy. Old saved scores
  are not remapped; opening-key misses and ambiguous cases still need review.
  Full MuseScore parity stays queued. Evidence:
  `/tmp/note-vision-accidentals-2033/` (source crops, focused/before/full logs,
  seven-score comparison and phone QA).
- Counterexample at this checkpoint: sparse row 1/bar 3's second E lacks its
  sharp. Its `symbol-106` box overlaps head `symbol-819`; the ordinary matcher
  rejects that negative gap and attaches it later. This first-note rule keeps
  that existing body association unchanged. E-flat carry is notation-consistent
  but does not make those later E pitches match the source. Changed sounding
  pitches are not all verified accuracy gains. Tight-overlap body-accidental
  association is addressed in the follow-up below; other missing/misread
  symbols and full parity remain queued.
- **Realme release 2033 passed fresh QA:** pixel-identical recent dense,
  sparse and song copies detect **225/175/117 symbols**, **9/8/5 staves**.
  Dense (**172 notes / eight rests / 27 bars**) restores both written flats
  and three key contexts. Sparse (**137/eight/24**) restores its first E-flat
  with unchanged keys. Four/three sounding-alteration changes follow the
  reconstructed keys/carry; they are not all confirmed accuracy gains (see
  the counterexample above). All other written fields and bar distributions
  are preserved. Song (**92/ten/15**) is musically identical to release 2031;
  only XML encoding date changes, and its PDF is pixel-identical.
- All PDFs are one page and visually checked; Play/Stop passed. All three
  new scores cold-reopen with byte-identical exports. Existing dense and
  old-build sparse baselines remain byte-identical after installation.
  Previous **42 projects** retained, **46 total** including four new QA
  projects. Original font/rotation and Home restored; temporary device helpers
  removed, recent copies retained, source originals unchanged. Thirteen exports
  archived/checksummed in `Download/NoteVisionQA2033/`. **94 retained app log
  lines** have no Flutter/crash/save errors. No subjective listening claim.
  Facts: `/tmp/note-vision-accidentals-2033/phone/qa-facts.json`.
  Tested APK SHA-256:
  `e6d015ed0ba023dfe439c7526bd967fc57f70ab783fc693c4512827086de7977`.

### Body accidentals overlapping their noteheads — 2026-11-09

- Reproduced the sparse row 1/bar 3 failure: the sharp's box ends slightly
  inside its intended second E head. The ordinary matcher rejected the
  negative gap and attached it to a later, misread A. A unique tight-overlap
  match now takes precedence, consuming the glyph once at the intended head.
- New matches require five staff lines, finite, staff-sized boxes, at most
  one-quarter head-width overlap and pitch alignment within .35 staff spaces.
  Flat loops use the lower part of the glyph; other accidentals use its centre.
  Alignment follows the staff slope and the same refined pitch head used by
  `PitchCalculator`. Competing heads/glyphs and existing ordinary bindings
  retain the previous association. Positive-gap matching and signature
  inference retain their existing rules.
- **43 new regressions** cover five accidental types, three scales, slopes,
  ambiguity/fallbacks, refined pitch geometry, the real sparse scan, JSON/XML
  and playback carry/reset. The initial regression run reproduced **32
  failures** before the implementation. Full **1,240 passed**; analysis clean;
  diff check clean. The first full run timed out in an existing review-widget
  `pumpAndSettle`; that six-test file passed alone, and the entire suite passed
  with concurrency 2. No editor test or production UI was changed for the retry.
- Seven replays use the exact archived detector outputs from release 2033.
  Only written accidental assignments change in dense, bass, mixed and sparse;
  ragged, song and clef-only scores are identical. Source crops were inspected
  for all affected bars. Notes/rests, steps/octaves, rhythms, keys, barlines and
  source geometry are unchanged. This fixes association, not the classifier:
  missing/repeated glyphs, misread heads and uncertain glyph classes still need
  review. It is not a broad transcription-accuracy claim. Full parity remains
  queued. Evidence: `/tmp/note-vision-body-2034/`.
- **Realme release 2034 passed fresh QA:** sparse **175 symbols / 8 staves**,
  **137 notes / 8 rests / 24 bars**; dense **225 / 9**, **172 / 8 / 27**; song
  **117 / 5**, **92 / 10 / 15**. Sparse's sharp moves to its second E and leaves
  the misread later A; dense has seven written-accidental field changes.
  Each has three sounding-alter changes under the existing key/carry rules;
  all other exported fields are preserved. The prior dense phone baseline has
  one fewer preceding note than the replay: affected pitches align by occurrence
  before comparison against the phone baseline. Song is musically unchanged,
  and its PDF raster is pixel-identical to 2033. All three PDFs are one page,
  visually checked; Play/Stop passed, without a subjective-listening claim.
- All three new projects cold-reopen with byte-identical XML. Existing sparse
  export is preserved across installation apart from the date across midnight.
  Previous **46 projects** retained, **49 total**; eleven exports archived and
  checksummed in `Download/NoteVisionQA2034/`. **466 retained app log lines**,
  no Flutter/crash/save errors. Original font/rotation/Home restored; temporary
  helpers removed; recent copies retained and source originals unchanged.
  Facts: `/tmp/note-vision-body-2034/phone/qa-facts.json`. Tested APK SHA-256:
  `e64073779a3669a83449d37c467ee8c620b27efbed278581902e9a0b469e08c9`.

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
- Follow-up (2026-11-04): letters, 0 (rest), + and drum keys write over
  what follows the input position in their voice, as MuseScore's note input
  does. A selected rest is written over; with nothing selected input starts
  after the bar's last note (a new score's pickup rest is written over and
  the pickup keeps its length); a note partly written over leaves rests for
  its remaining time; a value longer than the bar has left is split at the
  barline and tied into the next bar(s), adding bars at the end; ties and
  slurs of notes written over are removed. One undo step. Tapping or
  dragging onto the staff still inserts at that place; another voice than
  the selection's, tuplets and bars without a meter keep inserting.
  Checked on the phone (release 2016): a 2-quarter pickup rest written over
  by C D; a half B with one beat left tied into the next bar; undo removed
  both pieces; a half F after E replaced G and A.
- Follow-up fixes (2026-11-04): overwrite fills 32nd-note gaps and leftover
  rests exactly; finer unrepresentable splits leave the score unchanged.
  Split ties retain their sounding alteration through barlines/key changes,
  and playback holds chains of three or more pieces as one note. The canvas
  and PDF draw 32nd flags, three beam levels and the 32nd rest glyph.
- Touch chord entry: select or enter a note, enable Add notes → Chord,
  then tap a pitch in its bar (above or below); duration/voice/staff come
  from its chord's base, duplicates are ignored. Each addition is undoable.
  Keyboard letters in Chord add above the selected note, as Shift+A–G does.
- Insert: Add notes → Insert or Ctrl/Cmd+Shift+A–G adds time at the input
  position, shifting later music within that bar and retaining all notes.
  A bar may grow beyond its meter; it is not automatically rebarred. Typed
  rests, drum input and tapped/dragged notes support the Insert option too.
  Complex retained-source insertions are refused when their live timeline
  cannot preserve the result. Behavior reference: MuseScore's
  [Insert input method](https://handbook.musescore.org/basics/alternative-note-input-methods#insert).
- Not yet: automatic chord entry at the horizontal position tapped (Chord
  currently targets the selected note); MuseScore's +/- marker for bars
  whose actual duration differs from the meter; explicit measure-duration
  properties; an underfull bar is not padded with rests after overwriting.
  Existing exact-source rhythm/export restrictions still apply.
- Verification: note-input regression tests cover timing, playback, undo/redo,
  saving and MusicXML round trips; `editor_note_entry_test.dart` covers
  input controls, shortcut modifiers, playback locks and phone/large-text/
  landscape/tablet layouts. Physical-device results follow below.
- Tests: `test/features/editor/domain/note_input_test.dart`, keyboard test in
  `editor_commands_test.dart`; full suite 990 passed, analysis clean.

Device QA (2026-11-04): **passed**, local release **2017**, built from
`c738255` with `flutter build apk --release --build-number 2017`, installed
as an update on Realme RMX1851 / Android 11 (API 30). No code fixes were
needed during this check. The user's test-before-next-feature requirement
is satisfied; the next parity follow-up can proceed.

- A bar with 1/32 left accepted a quarter E5 without crashing: 32nd + dotted
  eighth + 32nd across the barline, tied as a chain. Phone-generated MusicXML
  confirmed exact durations (1/8 + 3/4 + 1/8 quarters) and both ties.
  Undo removed the complete edit; Redo restored it.
- Overwriting part of a dotted 16th left a 32nd rest. Export confirmed C5
  (1 quarter), E5 (1/4), rest (1/8), F5 (1): the following onset stayed put.
- Entering a half F5 after an earlier F-sharp split it across a barline into
  B-flat major; both tied pieces exported as F-sharp. Native playback ran;
  the user confirmed clear audio.
- Chord taps added G4 above and A3 below a selected half C4, retaining half
  values and chord flags; repeating G4 added no duplicate. Undo/Redo worked.
- Insert added D4 after C4 in a full C4 D4 E4 F4 bar. With Insert disabled,
  ADB-injected Ctrl+Shift+G also inserted: export held C4 D4 G4 D4 E4 F4,
  six quarters in one bar, with the original music retained.
- Imported MuseScore's `27_guitar_and_tab` reference; the phone canvas and
  exported one-page A4 PDF hid TAB meter/rests while retaining them on the
  notation staff. The exported PDF was rasterized and visually inspected.
- Portrait, 1.8x system text with inspector scrolling, and settled landscape
  (2340x1080) inspected. Restored font scale 0.9, automatic rotation 1 and
  user rotation 0, exactly as found.
- Saved the pre-existing unsaved **NV Overwrite QA** before updating; all
  six original projects survived. Saved **NV32Gap2017** and **NVChord2017**
  separately (eight projects after restart). Force-stopped/relaunched,
  reopened NV32Gap2017, played its three-piece tie, and re-exported it:
  pitches, durations, chord flags and ties matched its pre-restart export.
  Left NV32Gap2017 open with playback stopped.
- The app's active 44.1 kHz stereo speaker track had zero underruns at both
  diagnostic captures (before and after cold restart). No crash, unhandled
  exception, overflow, RangeError or playback failure in inspected app
  process logs. This was an Android check; no iOS or physical keyboard test.
- Local evidence: `/tmp/note-vision-phone-2017/` (captures, five checked
  MusicXML exports, reopened export, PDF/raster, audio/process logs and
  `device.json`). QA source/export files remain in the phone's
  `Download/NoteVisionQA2017/`. Tested APK SHA-256:
  `0bded7519544deb4aab9ee90d4d421b0c1d55338f22f4a344dfd83b69f2ad72b`.

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
  the next harmony on the staff (across barlines, in play order) or the end of
  the part, as MuseScore plays them, without taking over note highlights. Transpose
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
  sounds. (Follow-up: instruments whose sound, volume, pan, mute and solo
  are identical, such as a band's Clarinet 1–3, share one channel, so the
  Concert band template with every part playing uses exactly 15.) Several solo strips can sound together; explicit mute wins.
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
  non-GM banks and separate voice or harmony strips. Basic percussion maps,
  kit selection and transposing notation were added in 5C/5D. Unsupported
  imported instrument metadata stays in source; sound changes in multiple
  pitched-instrument or non-GM source declarations still refuse preserving
  export explicitly. GM percussion kit/volume/pan edits patch all declared
  pieces without replacing their IDs or unpitched mappings (5C follow-up).
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
- Follow-up: the courtesy natural is kept and chord symbols sound until the
  next chord (notation **41/41**, playback **45/75**). The other 30 are
  explained, not bugs: MuseScore gives an instrument it identifies from
  `<score-instrument>` (piano, flute, ...) a default `gateTime` of 95, so its
  MIDI releases each note about 5% early (a part with no declared
  instrument, or one it maps to a 100 gate, plays full length; this is also
  the release gap in `15_ensemble` and `20_instrument_mix`). The unison C♯ in
  bar 4 is cut to zero length in its MIDI export where Note Vision holds it
  with note-off counts. Note Vision plays notes for their full value.
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
  builds the parts: grand staves as joined parts (`P1`, `P1-staff2`),
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
- Not yet: subtitle/lyricist/copyright fields, saving user templates,
  minor-key names, irregular pickups needing two rests.
- Follow-up templates: Jazz combo, Big band, Concert band, Small concert
  band, Classical orchestra, Symphony orchestra, String orchestra and SATB + Organ (26 templates
  in all, each matching MuseScore's part names, sounds, clefs and transpositions).
  `NewStaff` is a class with an optional `program` (a jazz band's guitar is
  electric). `instrumentKey` reads "Horn in F 1 & 2" and "Trombone 3 &
  Bass Trombone" as one instrument; piccolo, E♭ clarinet, bari sax,
  timpani, glockenspiel, organ, string sections and generic percussion
  gained their MuseScore sounds/transpositions. The jazz, band and Classical
  orchestra template files store written keys in an older form that
  MuseScore's command-line export drops, so their keys are checked against the template files
  (B♭ parts 2 sharps, E♭ parts 3, horns 1 in concert C, as Note Vision
  writes them). Not yet: marching, brass band, bluegrass,
  barbershop, closed-score, liturgical and pit/battery percussion
  templates (they need further percussion maps/kits,
  shared-staff voices or instruments not yet in the tables).
- Classical orchestra (2026-11-04): matches MuseScore Studio **4.7.5**'s
  template instrument names, order, sounds, clefs and transpositions:
  12 instruments / 13 staves. The horns have two independent treble staves
  (`NewStaff.lowerClef`) with F transposition on both; edits to one do not
  duplicate notes onto the other. Both share their MIDI sound/channel;
  the complete orchestra uses **eight pitched channels**, leaving channel 10
  reserved for percussion. Clarinets/trumpets use B♭ transposition and the
  contrabass sounds an octave below its written pitch.
  `Part.squareBracket` retains the horn pair's square bracket through
  project JSON, `copyWith`, canvas/PDF and MusicXML `<part-symbol>`; import
  also recognizes MuseScore's square part-group around one instrument.
  Detaching the lower staff clears its bracket and undo restores it.
  Family brackets spanning different instruments remain unsupported.
  Reference: `reference/templates/01-Classical_Orchestra.musicxml`,
  regenerated by `tool/musescore_reference.sh`; the two horn written keys
  are checked separately because MuseScore's legacy template export drops
  them. Tests cover creation at phone, landscape and enlarged-text sizes,
  written/concert keys, independent horn playback, channel sharing,
  MusicXML round-trip, persistence, detach/undo and canvas/PDF rendering.
  Verification: `flutter analyze --no-pub` clean; full
  `flutter test --no-pub --reporter expanded` **998 passed**. Wizard tests
  also passed with the app's fonts and screenshot capture enabled (**7**).
  Local captures/PDFs: `/tmp/note-vision-classical-qa/` (visually checked).
  **Device QA passed (2026-11-05):** local release **2018**, Realme RMX1851
  / Android 11. Created through the wizard as **NVClassical2018** (two bars).
  Entered independent whole notes G4/B4 on the horn staves; undo of the
  lower note retained the upper note, redo restored it. Concert pitch showed
  C4/E4 on both horn staves with no sharps, and undo restored written pitch.
  Mixer showed 12 strips, one for the horn pair with French horn sound.
  Playback ran; the active 44.1 kHz stereo speaker track had zero underruns
  at capture. Subjective listening check deferred; user could not listen.
  Phone MusicXML verified 12 instruments / 13 staves, names, sounds, written
  keys, two treble horn clefs, F transposition, distinct staff-tagged notes
  and the square bracket. PDF exported and visually checked. Re-import
  retained the score and produced XML-equivalent output; the existing
  source-preservation warning remains (complex-source editing restrictions
  still apply). Saved project survived a cold restart with a byte-identical
  export. All eight previous projects retained (nine total). Enlarged text
  (1.8x) and landscape checked; font scale 0.9 and original rotation settings
  restored. Temporary keyboard helper removed. No iOS test.
  Evidence: `/tmp/note-vision-phone-2018/`; phone exports in
  `Download/NoteVisionQA2018/`. Tested APK SHA-256:
  `ec8449980f9b3e830aed8b68a91a201fa6cbbb575617c570a8d7ecbfcc7a00f0`.
- Symphony orchestra (2026-11-05): **25 instruments / 26 staves**, matching
  MuseScore Studio **4.7.5**'s template names, order, programs, clefs and
  transpositions (`reference/templates/02-Symphony_Orchestra.musicxml`).
  The harp has independent treble/bass staves with one sound and brace;
  the two horn parts each use one treble staff. Legacy written keys are
  checked separately, as for Classical orchestra. **26 templates total**.
  `Part.staffLines` and `Part.drumMap` (serializable `DrumPiece` data) support
  one-line Snare Drum (38 snare / 37 side-stick), Bass Drum (36) and Cymbals
  (57). All sit on the line with stems up; old five-line drum kits retain
  their positions, heads and voices. The wizard and Staves sheet can add
  each of these instruments. Their own touch buttons and keyboard shortcuts
  enter mapped pieces; invalid kit shortcuts do not insert pitched notes.
  Newly added staves retain their chosen instrument when renamed/reordered
  before Apply; the rename dialog disposes its controller after the closing
  route is removed. A regression covers that complete flow and undo.
  Canvas/PDF draw one line, short barlines/repeats, beams and rests; whole
  rests hang from that line and selection/drag hit targets follow it.
  JSON and MusicXML preserve maps, noteheads and `<staff-lines>1`.
  Playback uses **11 pitched channels plus channel 10** for the three
  percussion parts. Fixed the existing melodic-bank selection for drums:
  channel 10 now selects SoundFont **bank 128**, including orchestral kit 48.
  The bundled font's eight percussion presets have kit labels in the mixer.
  Percussion parts share kit/volume/pan settings; mute/solo remain per part,
  and Apply/undo update the whole change atomically. Imported GM percussion
  mix edits patch all corresponding MIDI declarations, keeping piece IDs,
  mappings, device metadata and note XML intact.
  Large-ensemble PDF layout reserves physical title/composer space when
  shrinking notation to A4; the full 26-staff score no longer overlaps its
  header. Targeted checks cover template parity, channels/bank selection,
  maps, touch/keyboard input, undo, persistence, import/export, the wizard,
  shared kit mixing and PDF header clearance. Canvas/PDF and phone-size,
  landscape and enlarged-text control captures were visually checked in
  `/tmp/note-vision-symphony-qa/`.
  Final verification: `flutter analyze --no-pub` **no issues**;
  `flutter test --no-pub --reporter expanded` **1,014 passed**;
  `git diff --check` clean. Full log:
  `/tmp/note-vision-symphony-full-tests.log`.
  **Device QA passed (2026-11-05):** local release **2019**, Realme RMX1851
  / Android 11. Created **NVSymphony2019** through the wizard (two bars).
  Snare button, A shortcut and touch entered keys 38/37/38 with the side-stick
  x head; invalid shortcut C inserted nothing. Bass drum and cymbal touch
  entry exported keys 36/57. Harp G4/C3 notes were independent across its
  treble/bass staves; undo/redo retained the other staff's note.
  MusicXML verified all 25 instruments / 26 staves, programs, clefs,
  one-line percussion maps and seven entered notes. Exported A4 PDF was
  visually checked: title/composer clear above all 26 staves.
  Mixer showed one harp strip; changing snare to Brush kit, volume 50%, pan
  47 degrees left updated all three percussion parts. Bass drum stayed
  unmuted when snare was muted. Export verified each shared setting, and
  one undo restored the whole mix. Added a snare to a separate piano score,
  renamed it **SideDrum2019** and moved it first before Apply; its one-line
  map, palette, sound and entered snare note survived undo/redo and export.
  Saved as **NVRename2019**. Both saved projects cold-reopened with
  byte-identical MusicXML exports. All nine previous projects retained
  (11 total). Enlarged text (1.8x), scrolling to percussion buttons and
  landscape checked; font scale 0.9 and original rotation settings restored.
  A staggered 26-note fixture exercised every instrument and both harp
  staves through import/playback/export. All 26 note elements were retained
  unchanged. The existing source-preservation import warning still appears.
  Native and imported playback ran; Android's active 44.1 kHz stereo track
  had zero underruns at capture. Subjective listening remains deferred
  because the user could not listen. Temporary keyboard helper removed;
  saved Symphony left open with playback stopped. No iOS test.
  Evidence: `/tmp/note-vision-phone-2019/`; phone exports in
  `Download/NoteVisionQA2019/`. Tested APK SHA-256:
  `8a1b82d4435f926da9419552aa6968af6cb33f939297a2f6c911cc85aa486849`.
  Family brackets, custom kit editing, rolls/sticking and marching templates
  remain incomplete. Retained-source rhythm/structure editing restrictions
  still apply; iOS percussion playback remains unverified.

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
- Follow-up: chord symbols in transposing parts now sound at concert pitch
  (they played as written) and are voiced from the concert-pitch chord, so
  written and concert-pitch views sound alike; Concert pitch already
  rewrote them.
- Not yet: per-instrument concert-pitch clefs; transposition changes
  mid-score.

## Stage 5D (part 2) — drum kit and percussion staves

- `Clef.percussion` (MusicXML `<sign>percussion</sign>`, no line) makes a
  drum staff (`Part.isPercussion`): no key signature, two-bar clef, notes
  placed as on a treble staff (`layoutSign` `P`). `Note.drum` is the kit
  piece's GM key; `step`/`octave` are its display position. `Note.notehead`
  (`x`, `circle-x`, `diamond`, …) is drawn in editor and PDF.
- `drumKit` (`drum_kit.dart`): MuseScore Studio's standard kit positions,
  heads, voices and letters (A bass drum, B snare, C closed hi-hat, D open
  hi-hat, E crash, F ride, G high tom, H floor tom). Hands stem up, feet
  (voice 2) down, also in a single-voice bar.
- MusicXML: `<unpitched>` notes import (previously dropped) with their kit
  piece from `<midi-unpitched>` (1-based), else by position; export writes
  them with `<instrument>` and the kit declared as MuseScore does (ids
  `P1-I<key+1>`, channel 10). Editing a drum note's piece in an imported
  file refuses retained-source export explicitly.
- Playback: drum notes sound their kit key on MIDI channel 10, shared by all
  drum staves. Transpose leaves drum staves alone.
- Editor: on a drum staff, Add notes shows the kit (name · letter); A–H
  enter pieces in their voices; outside note entry a letter changes the
  selected note's piece; tapping the staff enters the piece written at that
  height. Staves sheet adds Drum Kit; the Rock band template (vocals,
  electric guitars, bass guitar, drum kit) matches MuseScore's. Band guitar
  and bass sounds follow MuseScore.
- Parity: `24_drums` (rock beat, crash, ride, floor tom, open hi-hat):
  notation 22/22, playback 35/35 (facts now include kit piece and notehead).
- Device check (release **2010**, Realme RMX1851 / Android 11): Rock band
  created in the wizard; hi-hat, snare and bass drum entered with the kit
  buttons and drawn correctly; More → Concert pitch toggled (then restyled
  with a checkbox icon to match the menu).
- Follow-up: one-line orchestral percussion, kit selection and the correct
  playback bank are recorded in Stage 5C (Symphony orchestra). Timpani,
  jazz combo and concert band templates are also available.
- Not yet: MuseScore's separate input cursor per drum voice (a new voice 2
  starts at the selected note, as for pitched voices), custom kit editing,
  rolls and sticking.

## Stage 5D (part 3) — guitar tablature

- `Clef.tab` (MusicXML `<sign>TAB</sign>`, written without a line) makes a
  tablature staff (`Part.isTab`) with `Part.tabTuning` (open strings as MIDI,
  lowest first, from `<staff-details>` `<staff-tuning>`; standard guitar
  E2 A2 D3 G3 B3 E4 when absent). `Note.string` (1 = highest) and
  `Note.fret` come from `<technical>`. Pitch stays the sounding pitch, so
  playback and transposition are unchanged (MuseScore's MIDI agrees).
- `tabPosition` / `tabPlace` choose a string and fret (the note's own string
  when it reaches, else the lowest fret); `placeTabNotes` runs after every
  edit, so moving a tab note changes its fret on the same string. Export
  always writes string and fret, and no accidentals on TAB staves, as
  MuseScore does.
- Drawing (editor and PDF): a line per string inside the staff's height,
  TAB clef, no key signature, fret numbers on white over their string; no
  noteheads, stems or beams (MuseScore's simple tab). Selection, ties and
  slurs attach to the fret numbers.
- Editor: tapping a TAB staff in note entry enters the string tapped, open;
  Up/Down then change the fret. Letters enter pitches placed automatically.
  Staves sheet adds Guitar TAB; the Guitar tablature template matches
  MuseScore's.
- Parity: `25_tablature` (single notes, chords, sharps): notation 20/20,
  playback 29/29 (facts now include string, fret and tuning).
- Device check (release **2011**, Realme RMX1851 / Android 11): Guitar
  tablature created in the wizard; taps on strings 6, 5, 3 and 1 entered
  open strings on those strings; the Up key moved the top note to frets 1
  and 3 on string 1.
- Not yet: rhythm stems on tab, entering frets by number, bends, slides,
  hammer-ons, other tunings and string counts from the editor (imported ones
  are kept), bass tab.

## Stage 5D (part 4) — cross-staff notes

- `Note.staffMove` (MuseScore's staff move): the note stays in its own
  staff's voice and rhythm and is drawn one staff below (+1) or above (−1)
  within its instrument. MusicXML writes `<staff>` as home + move.
- Import: in a part on several staves each voice has a home staff, the one
  most of its notes sit on (`homeStaves`); its notes elsewhere become
  cross-staff instead of moving to the other staff's part (which had put
  them at the wrong time). The retained-source timeline uses the same home
  staves.
- Drawing (editor and PDF): a moved note sits on the other staff in that
  staff's clef, with its ledger lines; stems and beams join it to its
  voice, giving cross-staff beams.
- Editor: Ctrl/Cmd+Shift+Down/Up, search commands and Edit-dock Staff
  down/up tiles (shown only on a staff of a multi-staff instrument) move the
  selected note; one undo step.
- Parity: `26_cross_staff` (beamed right-hand eighths dipping into the bass
  staff, a cross-staff quarter): notation 20/20, playback 27/27.
- Device check (release **2012**, Realme RMX1851 / Android 11): a Piano
  score from the wizard, C4 E4 G4 C5 entered, Staff down moved C4 onto the
  bass staff at its own beat.
- Not yet: moving a whole range or chord at once, cross-staff rests,
  tapping a moved note on the other staff selects that staff's bar (select
  it with the arrows), beam slant and stem lengths tuned for cross-staff,
  voices whose notes sit mostly on the other staff after import keep that
  staff as home.

## Follow-up — Guitar + Tablature (linked staves)

- `Part.linked`: a TAB staff joined below a notation staff that shows the
  same music, as MuseScore's linked staves. `syncLinkedStaves` (in
  `_updateState`, before `placeTabNotes`) copies whichever staff an edit
  changed to the other; each staff keeps its clefs and its symbols' review
  IDs, staff and voice numbers, so retained-MusicXML patching still finds
  every note. Undo restores both together.
- Only the notation staff plays (playback and chord symbols skip linked
  parts); the genre model, notation checker and symbol counts skip them too.
- MusicXML: MuseScore writes a linked TAB staff's notes again on staff 2
  (voice 5) and does not link them again when it imports the file. Note
  Vision links an imported TAB staff whose rhythm and sounding pitches repeat
  the staff above (`linkRepeatedTabStaves`). Export writes both staves, a
  numbered key/time per staff hidden on the TAB staff, and TAB rests hidden,
  as MuseScore does. A patched (retained) export now updates a TAB note's
  string and fret and writes no accidental on it.
- Editor: Guitar + tablature template (MuseScore's 02-Guitar_+_Tablature);
  Staves and instruments adds "Guitar + TAB"; moving the TAB staff away
  unlinks it. The two staves are joined at the left without a brace or
  barlines through both (editor and PDF).
- Fixed (affected all tablature): a fret's tap target was placed at its
  note's pitch height instead of on its string, so frets on the canvas could
  not be selected by tapping.
- Parity: `27_guitar_and_tab.mscx` (single notes, a chord, a rest):
  notation 29/29, playback 17/18 (MuseScore also declares the guitar's muted
  channel, program 28). The template matches MuseScore's staves and sound.
- Device check (release **2014**, Realme RMX1851 / Android 11): Guitar +
  tablature from the wizard; four A3s entered on the notation staff showed
  fret 2 on string 3; tapping the first fret selected it, Up twice made it C4
  at fret 5 and the notation staff followed; undo gave B3 / fret 4 on both;
  saved and played. Saved test project: **NV Guitar Tab QAZ**.
- Follow-up (2026-11-04): simple TAB hides initial and changed time signatures
  and rest glyphs on the editor canvas and in PDF output, matching the
  hidden meter/rests in MuseScore's `27_guitar_and_tab` MusicXML reference.
  Shared signature metrics reserve no room for hidden TAB meters. Raster
  tests check that TAB is unchanged when rests/meters are removed while
  ordinary notation still draws them. Release **2017** (`c738255`) passed
  the phone canvas and exported-PDF check; see the Stage 3A device checkpoint.
- Not yet: ties are drawn on the notation staff only; linking an existing
  staff from the Staves sheet; other linked pairs (e.g. two notation staves).

Stage 5D is complete: transposing instruments, drums, tablature and
cross-staff notes. The agreed stage list is finished; remaining work is the
"Not yet" items of each stage and the inventory's engraving and platform
rows. Retained-source rhythm export for complex documents,
global timewise measure slots and richer editable notation still need work;
continue using the Stage 2B timeline rather than adding flat-list timing rules.

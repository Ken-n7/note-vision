# Barline regression photos

Handwritten practice photos prepared on Realme RMX1851 /
Android 11 with the image picker's Bitmap resize (filter=false, max 1200 px)
and JPEG quality 82. The original three sources are: IMG_20261015_211453_957 (bass/paired),
IMG_20261015_211418_667 (mixed), IMG_20261015_211721_162 (dense).

Detection JSON freezes B9 v2 A postprocessing from these inputs, using local
LiteRT 2.3 CPU inference. These are not captured phone detector outputs. The test
replays barline finding and reconstruction without running or tuning the
model. `boundaries.json` records visually checked staff-specific barline x
coordinates; it is not a complete musical transcription or an unseen-photo
accuracy benchmark. Three photos cover 22 staves and 45 interior barlines.

The paired sheet's first bass row previously mapped 20 detected notes to
bars [1, 2, 17]. The written boundaries map them to [3, 8, 9]. Two additional
notes in the first source bar were missed by the model and remain missing.
The regression preserves every detected note/rest ID and its reading order.
Physical release 2024 gives [3, 9, 8] on this row and preserves its prior
139 detected notes exactly. Local and phone detector outputs differ slightly;
both retain the written boundaries. Do not use replay note counts as an exact
phone-transcription oracle.
The other two photos retain their previous musical score exactly.

Diagnostics: `tool/barline_trace_test.dart`; work and native resize helper:
`/tmp/note-vision-bar-placement-2024/`. The Dart linear-resize approximation
in older evaluation tools does not reproduce Android's nearest-neighbor
Bitmap preparation; do not equate its outputs with fresh phone results.

Additional release-2024 QA inputs (added for the release-2025 regression fix):

- sparse: IMG_20261015_211244_372; real row-7 barline at x≈353 was vetoed.
- ragged: IMG_20261015_211432_497; real row-4 barline at x≈743 was vetoed.
- song: IMG_20261015_211622_458; unchanged reconstruction control.
- clefs: IMG_20261015_211332_790; clef-writing negative control, no notes/rests.

These four JSON files freeze the previous finder output. Their tests require
the two confirmed lines to return and other boundary assignments to stay stable;
they do not label all written boundaries. The sparse input still contains an
extra synthesized staff, and the song/uneven examples still have missed
boundaries/rests and padded bars. Keeping those frozen control outputs stable
for this isolated fix is not an assertion that their transcription is correct.
All seven fixtures contain 50 detected staff entries (one is a false extra
staff), rather than 50 independently verified written staves.

The head veto now requires consecutive broad ink rows spanning at least a third
of a staff space, with a peak width over half a space (and existing stroke-width
guards). This distinguishes head-sized ink from small staff-line fragments or
a neighboring head's edge. Tapered heads need not meet the peak width on every
row. Synthetic tests exercise both fragments and real missed heads at two scales.
Evidence: /tmp/note-vision-barline-regressions-2025/.

Meter regression (release 2026) reuses these unchanged detections. Sparse's
off-column `symbol-2` is a false timeSig4 near the key; the aligned real digits
give 4/4. `time_signature_real_scan_test.dart` checks that stack and the six
other meter/control baselines. Missing or misclassified digits in these
inputs are not musical ground truth and do not justify borrowing a meter.

Staff recovery regression (release 2027) decodes the sparse photo's frozen
G-clef boxes through `detectFromOutput` on this JPEG. The image's eight actual
traced rows must not gain a ninth from the merged clef box. The frozen JSON
continues to contain the old extra staff so earlier barline/meter tests retain
their original inputs. New full-output replays retain eight rows of three bars;
new mapped scans also stop padding shorter rows to match a longer row. The
uneven photo's 21-bar beat fallback and missing symbols remain unresolved.

Unresolved-row regression (release 2028): ragged's last two source rows have
no internal barlines. Their full note sequences now remain as one reviewable
row apiece (`unresolvedBarlines`) instead of 21 and five guessed measures.
Song's second row also remains unresolved, because its real x≈343/x≈612 lines
were missed after a short staff trace. Neither case justifies inventing
boundaries from beat totals. Frozen input JSON is unchanged; new tests verify
persistent review context and preserve all detected notes/rests.

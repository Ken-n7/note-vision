# Barline regression photos

Three existing handwritten practice photos, prepared on Realme RMX1851 /
Android 11 with the image picker's Bitmap resize (filter=false, max 1200 px)
and JPEG quality 82. Sources: IMG_20261015_211453_957 (bass/paired),
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

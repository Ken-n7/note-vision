# PDF/Editor Parity — Remaining Checks

Deferred: 2026-05-15

## Current status

The main PDF/editor parity fixes are in place:

- PDF page layout follows the editor page/system behavior.
- PDF notation uses the same embedded music/text fonts as the editor.
- Noteheads, stems, beams, rests, dots, accidentals, and clefs share core metrics.
- Treble clef placement has been tuned separately for PDF and editor.

## Remaining polish pass

These items are not blocking the current branch, but should be checked before
calling the export parity work fully done.

1. Time signature placement
   - Compare `4/4`, `3/4`, and other common signatures in the editor and PDF.
   - Check vertical centering between the staff lines.
   - Check spacing between clef, key signature, and time signature.

2. Accidentals
   - Compare sharp, flat, natural, double-sharp, and double-flat placement.
   - Check horizontal gap from the notehead.
   - Check vertical alignment for notes on lines and spaces.

3. Rests
   - Compare whole, half, quarter, and eighth rest placement.
   - Check vertical positions against the staff in editor and PDF.
   - Confirm dotted rests keep their dot in the same relative place.

4. Augmentation dots
   - Compare dotted notes and dotted rests.
   - Check horizontal spacing after noteheads/rests.
   - Check vertical offset for notes on lines vs spaces.

5. Note and stem spacing
   - Check stem attachment on quarter/eighth notes.
   - Check beam placement for grouped eighth notes.
   - Confirm note centers still match between editor and PDF after font changes.

## Final QA

Use the same sample score in the editor and exported PDF.

Check:

- Clef placement on every staff row.
- Time signature and key signature placement.
- Notes, rests, accidentals, dots, stems, flags, and beams.
- Page breaks and system wrapping.
- Mobile editor view vs exported PDF preview.

Run before final sign-off:

```bash
flutter analyze
flutter test
```

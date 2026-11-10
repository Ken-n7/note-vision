"""Checks against the printed notation, run with the documented music21 runtime."""

import importlib.util
import json
from pathlib import Path
import unittest


@unittest.skipUnless(importlib.util.find_spec('music21'), 'Requires the documented music21 runtime')
class TranscriptionTest(unittest.TestCase):
    def setUp(self):
        import music21
        self.music21 = music21
        self.data = Path(__file__).parent / 'data'

    def bars(self, filename):
        score = self.music21.converter.parse(self.data / filename, format='abc')
        return list(score.parts[0].getElementsByClass(self.music21.stream.Measure))

    def test_each_manifest_excerpt_has_its_declared_length_and_complete_bars(self):
        records = json.loads((self.data / 'manifest.json').read_text())['pieces']
        for record in records:
            with self.subTest(work=record['id']):
                bars = self.bars(record['filename'])
                self.assertEqual(len(bars), record['bars'])
                events = [n for b in bars for n in b.notesAndRests]
                # As in the app, omit leading/consecutive rests.
                trimmed = []
                for n in events:
                    if n.isRest and (not trimmed or trimmed[-1].isRest):
                        continue
                    trimmed.append(n)
                self.assertEqual(len(trimmed), record['events'])
                for bar in bars:
                    self.assertAlmostEqual(float(bar.duration.quarterLength),
                                           float(bar.barDuration.quarterLength))

    def test_kung_hindi_man_retains_chromatic_notes_as_printed(self):
        bars = self.bars('kung_hindi_man.abc')
        self.assertEqual([n.pitch.midi for n in bars[0].notes], [62, 63, 62, 61])
        self.assertEqual([n.pitch.midi for n in bars[10].notes], [71, 72, 74, 75])

    def test_bituing_marikit_keeps_duple_meter_triplets_and_tie(self):
        bars = self.bars('bituing_marikit.abc')
        self.assertEqual(bars[0].timeSignature.ratioString, '2/4')
        self.assertEqual([n.pitch.midi for n in bars[8].notes], [63, 67, 67, 66, 67])
        self.assertEqual([n.pitch.midi for n in bars[13].notes], [71, 62, 71])
        self.assertEqual([n.pitch.midi for n in bars[14].notes], [69, 68, 69, 72, 66])
        self.assertEqual(bars[7].notes[0].tie.type, 'start')
        self.assertEqual(bars[8].notes[0].tie.type, 'stop')
        for n in bars[0].notesAndRests:
            self.assertAlmostEqual(float(n.quarterLength), 1 / 3)

    def test_jocelynang_baliwag_is_the_lower_vocal_line(self):
        bars = self.bars('jocelynang_baliwag.abc')
        self.assertEqual([n.pitch.midi for n in bars[0].notes], [76, 71, 74, 72])
        self.assertEqual([n.pitch.midi for n in bars[6].notes], [71, 74, 65, 69, 62, 65])

    def test_verified_ikaw_rin_keeps_printed_triplets_and_tie(self):
        bars = self.bars('ikaw_rin_verified.abc')
        self.assertEqual(len(bars), 12)
        self.assertEqual(bars[0].timeSignature.ratioString, '2/4')
        self.assertEqual([n.pitch.midi for n in bars[1].notes], [65, 67, 69, 65])
        self.assertEqual([n.pitch.midi for n in bars[11].notes], [69, 71, 72, 76])
        for i in (1, 3, 9, 11):
            self.assertTrue(bars[i].notesAndRests[0].isRest)
            for n in list(bars[i].notesAndRests)[:3]:
                self.assertAlmostEqual(float(n.quarterLength), 1/3)
        self.assertEqual(bars[4].notes[-1].tie.type, 'start')
        self.assertEqual(bars[5].notes[0].tie.type, 'stop')
        for bar in bars:
            self.assertAlmostEqual(float(bar.duration.quarterLength), 2.)


if __name__ == '__main__':
    unittest.main()

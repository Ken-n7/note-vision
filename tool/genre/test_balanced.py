import importlib.util
from pathlib import Path
import tempfile
import unittest


@unittest.skipUnless(importlib.util.find_spec('numpy'), 'Requires the documented NumPy runtime')
class BalancedBankTest(unittest.TestCase):
    def setUp(self):
        import balanced
        import numpy
        self.balanced = balanced
        self.np = numpy

    def pieces(self, length=48, transpose_copy=False):
        pieces = []
        for g, genre in enumerate(('waltz', 'kundiman', 'jazz', 'other')):
            beats = (3, 3, 4, 2)[g]
            notes = [[60 + i * (g + 1) % 13, .5 + (i % 3) * .5, (i % beats) / beats, beats]
                     for i in range(length)]
            pieces.append(dict(name=genre, genre=genre, notes=notes))
            if transpose_copy:
                shifted = [[p + 12, d, at, meter] for p, d, at, meter in notes]
                pieces.append(dict(name=genre + '_octave', genre=genre, notes=shifted))
        return pieces

    def test_exact_balance_has_unique_valid_inputs_and_preserves_sources(self):
        pieces = self.pieces()
        before = self.balanced.fingerprint(pieces)
        bank, origins, stats = self.balanced.build_bank(pieces, 8, seed=7)
        self.assertEqual(self.balanced.fingerprint(pieces), before)
        hashes = []
        for genre, rows in bank.items():
            self.assertEqual(rows.shape, (8, 64, 22))
            self.assertEqual(rows.dtype, self.np.float32)
            self.assertTrue(self.np.isfinite(rows).all())
            self.assertEqual(stats[genre]['represented_source_pieces'], 1)
            for row, origin in zip(rows, origins[genre]):
                actual = row[:, 4:9].sum(1) > 0
                self.assertGreaterEqual(self.np.count_nonzero(actual & (row[:, 1] == 0)), 16)
                self.assertEqual(origin['genre'], genre)
                self.assertEqual(origin['source_name'], genre)
                hashes.append(origin['feature_sha256'])
        self.assertEqual(len(set(hashes)), 32)

    def test_octave_copy_is_not_an_additional_original_input(self):
        bank, _, stats = self.balanced.build_bank(self.pieces(16, True), 2, seed=11)
        for genre in bank:
            self.assertEqual(stats[genre]['source_windows'], 1)
            self.assertEqual(stats[genre]['augmented_windows'], 1)

    def test_loader_rejects_other_fold_changed_sources_and_changed_payload(self):
        pieces = self.pieces()
        bank, origins, stats = self.balanced.build_bank(pieces, 4, seed=3)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            self.balanced.save_bank(output, bank, origins, stats, pieces, 'all', 3)
            loaded = self.balanced.load_bank(output, pieces, 'all')
            self.np.testing.assert_array_equal(loaded['kundiman'], bank['kundiman'])
            with self.assertRaisesRegex(ValueError, 'different fold'):
                self.balanced.load_bank(output, pieces, '0')
            with self.assertRaisesRegex(ValueError, 'sources differ'):
                self.balanced.load_bank(output, pieces[:-1], 'all')
            with (output / 'origins.jsonl').open('a') as stream:
                stream.write('{}\n')
            with self.assertRaisesRegex(ValueError, 'payload changed'):
                self.balanced.load_bank(output, pieces, 'all')


if __name__ == '__main__':
    unittest.main()

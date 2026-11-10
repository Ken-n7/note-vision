import importlib.util
import unittest


@unittest.skipUnless(importlib.util.find_spec('torch'), 'Requires the documented Torch runtime')
class HardNegativeTest(unittest.TestCase):
    def test_mining_keeps_true_negative_labels_and_does_not_modify_sources(self):
        import numpy as np
        import torch
        from train import hard_negative_bank

        class Teacher:
            def __call__(self, x):
                result = torch.zeros((len(x), 4))
                result[:, 1] = x[:, 0, 0]
                return result

        rows = np.zeros((20, 64, 22), np.float32)
        rows[:, 0, 0] = np.arange(20) / 20
        bank = {g: rows.copy() for g in ('waltz', 'kundiman', 'jazz', 'other')}
        mined, counts = hard_negative_bank(Teacher(), bank)
        for genre in ('waltz', 'jazz', 'other'):
            np.testing.assert_array_equal(mined['hard_' + genre], rows[-2:])
            self.assertEqual(counts[genre]['windows'], 2)
            np.testing.assert_array_equal(bank[genre], rows)
        self.assertNotIn('hard_kundiman', mined)
        self.assertEqual(set(bank), {'waltz', 'kundiman', 'jazz', 'other'})


if __name__ == '__main__':
    unittest.main()

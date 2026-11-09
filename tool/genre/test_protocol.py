"""Mobile contract regressions; runs with the Python standard library only."""

import unittest

from protocol import app_label, features, key_of, windows


class MobileContractTest(unittest.TestCase):
    def test_matches_existing_dart_melody_fixture(self):
        # test/core/services/genre_model_test.dart is the independent app oracle.
        notes = [[60, 1, 0, 3], [-1, .5, 1 / 3, 3], [67, 1.5, .5, 3],
                 [83, 4, 0, 5], [66, 1, .8, 5]]
        self.assertEqual(key_of(notes), (11, True))
        rows = features(notes)
        self.assertEqual([[i - 9 for i in range(9, 21) if r[i]] for r in rows],
                         [[1], [], [8], [0], [7]])
        self.assertEqual([r[0] for r in rows], [0, 0, 7 / 12, 1, -1])
        self.assertEqual(rows[3][2], 1)
        self.assertEqual(rows[3][8], 1)

    def test_notes_after_mobile_cap_cannot_change_key_or_probabilities(self):
        prefix = [[60 + i % 3 * 4, 1, 0, 3] for i in range(320)]
        tail = [[61, 1000, 0, 3] for _ in range(200)]
        self.assertEqual(windows(prefix + tail), windows(prefix))
        self.assertNotEqual(key_of(prefix), key_of(prefix + tail))

    def test_window_counts_short_padding_and_unconsumed_tail(self):
        notes = [[60, 1, 0, 3] for _ in range(321)]
        self.assertEqual(windows(notes[:15]), [])
        self.assertEqual(len(windows(notes[:16])[0]), 64)
        self.assertEqual(windows(notes[:16])[0][:48], [[0.] * 22 for _ in range(48)])
        self.assertEqual(len(windows(notes)), 9)
        # A 65th row affects the key context but does not create a second window.
        self.assertEqual(len(windows(notes[:65])), 1)
        self.assertEqual(len(windows(notes[:96])), 2)

    def test_display_thresholds_are_frozen(self):
        minor = [[p, 1, 0, 3] for p in [69, 71, 72, 74, 76, 77, 80, 81] * 4]
        self.assertEqual(app_label([.1, .7, .1, .1], minor), 'kundiman')
        self.assertEqual(app_label([.1, .399, .1, .401], minor), 'waltz')
        self.assertEqual(app_label([.1, .4, .1, .4], minor), 'kundiman')
        self.assertEqual(app_label(None, []), None)
        self.assertEqual(app_label([.1, .1, .7, .1], minor), 'jazz')


if __name__ == '__main__':
    unittest.main()

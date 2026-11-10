import unittest

from audit import classification, explain, summarize, feature_overlaps


class AuditTest(unittest.TestCase):
    def test_raw_confusion_keeps_precision_recall_and_other_distinct(self):
        rows = [dict(expected='kundiman', baseline=[0, .8, 0, .2]),
                dict(expected='waltz', baseline=[.1, .8, 0, .1]),
                dict(expected='other', baseline=[0, 0, 0, 1])]
        result = classification(rows, 'baseline')
        self.assertEqual(result['accuracy'], 2 / 3)
        self.assertEqual(result['classes']['kundiman']['precision'], .5)
        self.assertEqual(result['classes']['kundiman']['recall'], 1.)
        self.assertEqual(result['classes']['kundiman']['f1'], 2 / 3)
        self.assertEqual(result['classes']['other']['recall'], 1.)

    def test_duple_kundiman_can_be_raw_correct_but_fall_back_to_jazz(self):
        notes = [[60, 1, 0, 2]] * 20
        self.assertEqual(explain([.01, .46, .09, .44], notes), 'rule_fallback')
        self.assertEqual(explain([.01, .8, .09, .1], notes), 'confident_model')

    def test_duplicate_prefixes_and_label_drift_are_rejected(self):
        piece = dict(name='a', genre='kundiman', source='fixture', notes=[[60, 1, 0, 3]] * 20)
        row = dict(name='a', split='test', prefix=40, expected='kundiman',
                   baseline=[0, 1, 0, 0], candidate=[0, 1, 0, 0],
                   baseline_app='kundiman', candidate_app='kundiman')
        with self.assertRaisesRegex(ValueError, 'Repeated'):
            summarize([row, row], [piece])
        with self.assertRaisesRegex(ValueError, 'labels disagree'):
            summarize([dict(row, expected='waltz')], [piece])

    def test_overlap_finds_octave_duplicate_without_relabelling_it(self):
        notes = [[60 + i % 7, 1, (i % 3) / 3, 3] for i in range(20)]
        train = dict(name='a', genre='waltz', notes=notes)
        test = dict(name='b', genre='kundiman', split='test',
                    notes=[[p+12, d, at, meter] for p, d, at, meter in notes])
        result = feature_overlaps([train], [test])
        self.assertEqual(result['evaluation_pieces_with_matches'], 1)
        self.assertEqual(result['matches'][0]['training_matches'], [dict(name='a', genre='waltz')])
        self.assertEqual(test['genre'], 'kundiman')


if __name__ == '__main__':
    unittest.main()

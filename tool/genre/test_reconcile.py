import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from reconcile import reconcile
from corpus import verify_reconciliation


def piece(name, split, genre='waltz', shift=0):
    return dict(name=name, genre=genre, source='fixture', split=split,
                notes=[[60 + i % 7 + shift, 1, (i % 3) / 3, 3] for i in range(40)])


class ReconcileTest(unittest.TestCase):
    def test_evaluation_wins_without_moving_or_mutating_original_rows(self):
        pieces = [piece('train_copy', 'train'), piece('valid_copy', 'valid', shift=12),
                  piece('test_copy', 'test', shift=-12)]
        before = copy.deepcopy(pieces)
        kept, report = reconcile(pieces)
        self.assertEqual([(p['name'], p['split']) for p in kept], [('test_copy', 'test')])
        self.assertEqual(pieces, before)
        self.assertEqual(len(report['excluded']), 2)
        self.assertEqual(report['residual_exact_window_matches'], 0)

    def test_conflicting_shared_inputs_are_quarantined_not_relabelled(self):
        kept, report = reconcile([piece('a', 'train', 'other'), piece('b', 'valid', 'jazz')])
        self.assertEqual(kept, [])
        self.assertEqual({r['reason'] for r in report['excluded']}, {'conflicting_labels'})

    def test_transitive_work_family_prevents_alias_from_staying_in_training(self):
        a = piece('a', 'train')
        b = piece('b', 'train')
        c = piece('c', 'fresh_test')
        b['notes'] = [[70 + i % 3, 2, (i % 2) / 2, 2] for i in range(40)]
        c['notes'] = copy.deepcopy(b['notes'])
        a['group_id'] = b['group_id'] = 'known_related_work'
        kept, report = reconcile([a, b, c])
        self.assertEqual([p['name'] for p in kept], ['c'])
        self.assertEqual(len(report['families'][0]['members']), 3)

    def test_shared_short_prefix_is_detected_even_if_later_keys_differ(self):
        a = piece('a', 'train')
        b = piece('b', 'test')
        b['notes'] += [[78, 3, 0, 3]] * 70
        kept, _ = reconcile([a, b])
        self.assertEqual([p['name'] for p in kept], ['b'])

    def test_reviewed_arrangement_family_groups_different_model_inputs(self):
        a = piece('a', 'train')
        b = piece('b', 'test')
        b['notes'] = [[70 + i % 3, 2, (i % 2) / 2, 2] for i in range(40)]
        kept, _ = reconcile([a, b], [dict(id='reviewed', members=['a', 'b'])])
        self.assertEqual([p['name'] for p in kept], ['b'])
        with self.assertRaisesRegex(ValueError, 'absent source IDs'):
            reconcile([a, b], [dict(id='stale', members=['a', 'missing'])])

    def test_snapshot_and_original_data_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            data = root / 'data'
            (data / 'out/genre').mkdir(parents=True)
            original = data / 'out/genre/pieces.json'
            original.write_text('[]')
            split = root / 'legacy-split.json'
            split.write_text('{"train": []}')
            report = dict(policy='shared_input_families_v1',
                          output_hashes={split.name: hashlib.sha256(split.read_bytes()).hexdigest()},
                          input_hashes={'pieces': hashlib.sha256(original.read_bytes()).hexdigest()})
            (root / 'reconciliation.json').write_text(json.dumps(report))
            verify_reconciliation(root, data)
            original.write_text('[{}]')
            with self.assertRaisesRegex(ValueError, 'Original data changed'):
                verify_reconciliation(root, data)
            original.write_text('[]')
            split.write_text('{"train": ["evaluation"]}')
            with self.assertRaisesRegex(ValueError, 'snapshot changed'):
                verify_reconciliation(root, data)


if __name__ == '__main__':
    unittest.main()

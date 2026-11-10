import unittest

from corpus import assert_disjoint, conflicting_labels, frozen_train, note_hash


class CorpusTest(unittest.TestCase):
    def test_alternate_passages_of_same_work_cannot_cross_splits(self):
        with self.assertRaisesRegex(ValueError, 'crosses'):
            assert_disjoint({'train': [{'name': 'verse', 'work_id': 'song'}],
                             'test': [{'name': 'refrain', 'work_id': 'song'}]})

    def test_conflicting_genres_are_quarantined_by_work(self):
        pieces = [dict(name='a', genre='jazz'), dict(name='a', genre='waltz'),
                  dict(name='verse', work_id='song', genre='kundiman'),
                  dict(name='refrain', work_id='song', genre='kundiman')]
        self.assertEqual(conflicting_labels(pieces), {'a': ['jazz', 'waltz']})
        assert_disjoint({'train': pieces})

    def test_related_compositions_cannot_cross_partitions(self):
        with self.assertRaisesRegex(ValueError, 'crosses'):
            assert_disjoint({'train': [dict(name='jocelynang', group_id='shared_family')],
                             'test': [dict(name='cundiman_1902', group_id='shared_family')]})

    def test_group_override_cannot_hide_a_shared_work(self):
        with self.assertRaisesRegex(ValueError, 'crosses'):
            assert_disjoint({'train': [dict(name='verse', work_id='song', group_id='a')],
                             'test': [dict(name='refrain', work_id='song', group_id='b')]})

    def test_training_selection_excludes_validation_test_and_fresh_sources(self):
        pieces = [dict(name=name, genre='kundiman') for name in ('a', 'b', 'c')]
        split = dict(train=['a'], valid=['b'], test=['c'])
        additions = [dict(name='new', genre='kundiman', split='new_train'),
                     dict(name='fresh', genre='kundiman', split='fresh_test')]
        self.assertEqual([p['name'] for p in frozen_train(pieces, split, additions)], ['a', 'new'])
        self.assertEqual([p['name'] for p in frozen_train(pieces, split, additions, ['a'])], ['new'])

    def test_verified_correction_preserves_source_identity_and_held_out_input(self):
        original = dict(name='a', genre='kundiman', notes=[[60, 1, 0, 2]])
        correction = dict(name='a', genre='kundiman', notes=[[60, 1/3, 0, 2]],
                          replaces_notes_sha256=note_hash(original['notes']), provenance={'verified': True})
        split = dict(train=['a'], valid=[], test=[])
        result = frozen_train([original], split, [], corrections=[correction])
        self.assertEqual(result[0]['notes'], correction['notes'])
        self.assertEqual(original['notes'], [[60, 1, 0, 2]])
        self.assertEqual(frozen_train([original], split, [], ['a'], [correction]), [])
        with self.assertRaisesRegex(ValueError, 'original training work'):
            frozen_train([original], dict(train=[], valid=['a'], test=[]), [], corrections=[correction])
        with self.assertRaisesRegex(ValueError, 'changed original notes'):
            frozen_train([dict(original, notes=[])], split, [], corrections=[correction])


if __name__ == '__main__':
    unittest.main()

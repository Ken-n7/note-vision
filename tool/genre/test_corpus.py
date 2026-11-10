import unittest

from corpus import assert_disjoint, conflicting_labels


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


if __name__ == '__main__':
    unittest.main()

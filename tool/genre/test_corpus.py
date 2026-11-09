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


if __name__ == '__main__':
    unittest.main()

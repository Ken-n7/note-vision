"""Work identity and label checks shared by preparation and training."""

from collections import defaultdict


def work_id(piece):
    return piece.get('work_id', piece['name'])


def conflicting_labels(pieces):
    labels = defaultdict(set)
    for piece in pieces:
        labels[work_id(piece)].add(piece['genre'])
    return {name: sorted(genres) for name, genres in sorted(labels.items()) if len(genres) > 1}


def assert_disjoint(parts):
    seen = {}
    for split, pieces in parts.items():
        for piece in pieces:
            work = work_id(piece)
            if work in seen and seen[work] != split:
                raise ValueError(f'{work} crosses {seen[work]} and {split}')
            seen[work] = split

"""Work identity and label checks shared by preparation and training."""

from collections import defaultdict


def work_id(piece):
    return piece.get('work_id', piece['name'])


def partition_id(piece):
    """Known related melodies share one split even with different work IDs."""
    return piece.get('group_id', work_id(piece))


def conflicting_labels(pieces):
    labels = defaultdict(set)
    for piece in pieces:
        labels[work_id(piece)].add(piece['genre'])
    return {name: sorted(genres) for name, genres in sorted(labels.items()) if len(genres) > 1}


def assert_disjoint(parts):
    seen = {}
    for split, pieces in parts.items():
        for piece in pieces:
            identities = (('work', work_id(piece)), ('group', partition_id(piece)))
            for identity in identities:
                if identity in seen and seen[identity] != split:
                    raise ValueError(f'{identity[1]} crosses {seen[identity]} and {split}')
                seen[identity] = split

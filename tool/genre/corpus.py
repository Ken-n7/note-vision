"""Work identity and label checks shared by preparation and training."""

from collections import defaultdict
import hashlib
import json
from pathlib import Path


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


def note_hash(notes):
    return hashlib.sha256(json.dumps(notes, separators=(',', ':')).encode()).hexdigest()


def training_corrections(root):
    path = Path(root) / 'training-corrections.json'
    return json.loads(path.read_text()) if path.exists() else []


def frozen_train(pieces, split, additions, held_out=(), corrections=()):
    """Select eligible original/curated works before deriving any examples."""
    allowed = set(split['train']) - set(held_out)
    blocked = set(split['valid']) | set(split['test']) | set(held_out)
    result = [p for p in pieces if p['name'] in allowed]
    originals = {p['name']: p for p in pieces}
    replacements = {}
    for correction in corrections:
        name = correction['name']
        if name not in split['train'] or name not in originals:
            raise ValueError('Training correction must target an original training work')
        original = originals[name]
        if name in replacements or correction['genre'] != original['genre']:
            raise ValueError('Repeated/mislabelled training correction')
        if note_hash(original['notes']) != correction['replaces_notes_sha256']:
            raise ValueError('Training correction targets changed original notes')
        if work_id(original) != work_id(correction) or partition_id(original) != partition_id(correction):
            raise ValueError('Training correction changes work/group identity')
        replacements[name] = dict(original, notes=correction['notes'],
                                  correction_provenance=correction['provenance'])
    result = [replacements.get(p['name'], p) for p in result]
    for p in additions:
        if p.get('split') == 'new_train' and work_id(p) not in blocked:
            result.append(p)
    if any(work_id(p) in blocked for p in result):
        raise ValueError('Work-level train/evaluation leakage')
    if conflicting_labels(result):
        raise ValueError('Training contains contradictory labels; run prepare.py first')
    evaluation = [p for p in pieces if p['name'] in blocked]
    evaluation += [p for p in additions if p.get('split') != 'new_train']
    assert_disjoint(dict(train=result, evaluation=evaluation))
    return result

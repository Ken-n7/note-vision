"""Freeze legacy song partitions and parse the attributed new ABC excerpts."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
import sys

from corpus import assert_disjoint, conflicting_labels, work_id
from artifacts import write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_root', type=Path)
    parser.add_argument('experiment', type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.data_root / 'scripts'))
    import genre_train as legacy
    from genre_prep import notes_of
    import music21

    pieces, inputs = [], {}
    for name in ('pieces', 'more', 'pdmx'):
        path = args.data_root / 'out/genre' / f'{name}.json'
        inputs[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        pieces.extend(json.loads(path.read_text()))
    legacy.PURE_SYNTH, legacy.KVALID_REAL, legacy.FOLD = True, True, 'all'
    parts = legacy.split(pieces, random.Random(7))
    # Split first: removing ambiguous rows must not reshuffle historic folds.
    quarantine = conflicting_labels(pieces)
    parts = {name: [p for p in ps if work_id(p) not in quarantine]
             for name, ps in parts.items()}
    assert_disjoint(parts)
    split = {name: [p['name'] for p in ps] for name, ps in parts.items()}
    all_names = [name for names in split.values() for name in names]
    if len(set(all_names)) != len(all_names):
        raise ValueError('Repeated source IDs require work-level reconciliation')
    additions = []
    data = Path(__file__).parent / 'data'
    for filename, name, split_name, source in (
        ('sa_silong_ng_langit.abc', 'kundiman_sa_silong_ng_langit', 'new_train',
         'https://imslp.org/wiki/Dakilang_Punglo_(Abelardo,_Nicanor)'),
        ('kundiman_1800.abc', 'kundiman_kundiman_1800', 'fresh_test',
         'https://collections.carli.illinois.edu/digital/api/collection/rou_cmct/id/49/download'),
    ):
        path = data / filename
        score = music21.converter.parse(path, format='abc')
        bars = list(score.parts[0].getElementsByClass(music21.stream.Measure))
        if any(float(bar.duration.quarterLength) != 3 for bar in bars):
            raise ValueError(f'{filename}: transcription has an incomplete/overfull bar')
        additions.append(dict(name=name, work_id=name, genre='kundiman', source=source,
                              split=split_name, notes=notes_of(score),
                              abc_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    evaluation = [dict(p, split=label) for label in ('valid', 'test') for p in parts[label]]
    evaluation += [dict(p, split='known_training') for p in parts['train']
                   if p['genre'] == 'kundiman']
    extra = args.data_root / 'out/genre/extra.json'
    inputs['extra'] = hashlib.sha256(extra.read_bytes()).hexdigest()
    evaluation += [dict(p, split='external_negative') for p in json.loads(extra.read_text())]
    args.experiment.mkdir(parents=True, exist_ok=True)
    for filename, value in (
        ('legacy-split.json', split), ('additions.json', additions),
        ('baseline-corpus.json', evaluation), ('input-hashes.json', inputs),
        ('quarantine.json', quarantine),
    ):
        write_json(args.experiment / filename, value, compact=True)
    print({name: dict(Counter(p['genre'] for p in ps)) for name, ps in parts.items()})
    print('New training works: 1; fresh test works: 1 (both excerpts, not complete songs)')


if __name__ == '__main__':
    main()

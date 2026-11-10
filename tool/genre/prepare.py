"""Freeze legacy song partitions and parse the attributed new ABC excerpts."""

import argparse
from collections import Counter
from datetime import date
import hashlib
import json
import math
from pathlib import Path
import random
import sys

from corpus import assert_disjoint, conflicting_labels, work_id, frozen_train
from artifacts import write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_root', type=Path)
    parser.add_argument('experiment', type=Path)
    parser.add_argument('--through', type=date.fromisoformat,
                        help='Use only excerpts curated through YYYY-MM-DD; preserves older experiments')
    parser.add_argument('--training-corrections', type=Path,
                        help='Opt-in source-verified replacements; evaluation note lists remain frozen')
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
    manifest_path = data / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    if manifest['schema_version'] != 1:
        raise ValueError('Unsupported curation manifest version')
    for record in manifest['pieces']:
        if args.through and date.fromisoformat(record['added_on']) > args.through:
            continue
        if record['split'] not in ('new_train', 'fresh_test'):
            raise ValueError(f"{record['id']}: unrecognized curated partition")
        path = data / record['filename']
        score = music21.converter.parse(path, format='abc')
        bars = list(score.parts[0].getElementsByClass(music21.stream.Measure))
        if any(not math.isclose(float(bar.duration.quarterLength),
                                float(bar.barDuration.quarterLength), abs_tol=1e-8)
               for bar in bars):
            raise ValueError(f'{path.name}: transcription has an incomplete/overfull bar')
        notes = notes_of(score)
        if len(bars) != record['bars'] or len(notes) != record['events']:
            raise ValueError(f'{path.name}: excerpt length changed; review its manifest')
        additions.append(dict(name=record['id'], work_id=record['id'],
                              group_id=record.get('group_id', record['id']),
                              genre='kundiman', source=record['source_url'],
                              split=record['split'], notes=notes, provenance=record,
                              abc_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    if len({p['name'] for p in additions}) != len(additions):
        raise ValueError('Repeated curated work IDs')
    corrections = []
    if args.training_corrections:
        correction_manifest = json.loads(args.training_corrections.read_text())
        if correction_manifest['schema_version'] != 1:
            raise ValueError('Unsupported training-correction manifest version')
        for record in correction_manifest['pieces']:
            if args.through and date.fromisoformat(record['added_on']) > args.through:
                continue
            path = args.training_corrections.parent / record['filename']
            score = music21.converter.parse(path, format='abc')
            bars = list(score.parts[0].getElementsByClass(music21.stream.Measure))
            notes = notes_of(score)
            if len(bars) != record['bars'] or len(notes) != record['events'] or any(
                    not math.isclose(float(b.duration.quarterLength),
                                     float(b.barDuration.quarterLength), abs_tol=1e-8) for b in bars):
                raise ValueError('Training correction has changed/incomplete notation')
            corrections.append(dict(name=record['id'], genre='kundiman', notes=notes,
                                    replaces_notes_sha256=record['replaces_notes_sha256'],
                                    provenance=dict(record, abc_sha256=hashlib.sha256(path.read_bytes()).hexdigest())))
        frozen_train(pieces, split, additions, corrections=corrections)
    assert_disjoint(dict(
        train=parts['train'] + [p for p in additions if p['split'] == 'new_train'],
        valid=parts['valid'], test=parts['test'] + [p for p in additions if p['split'] == 'fresh_test']))
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
        ('training-corrections.json', corrections),
        ('curation.json', dict(manifest_sha256=hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                               training_corrections_sha256=hashlib.sha256(args.training_corrections.read_bytes()).hexdigest()
                               if args.training_corrections else None,
                               through=str(args.through) if args.through else None,
                               included=[p['name'] for p in additions])),
    ):
        write_json(args.experiment / filename, value, compact=True)
    print({name: dict(Counter(p['genre'] for p in ps)) for name, ps in parts.items()})
    print('Curated excerpts:', dict(Counter(p['split'] for p in additions)))


if __name__ == '__main__':
    main()

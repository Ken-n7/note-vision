"""Build labelled, deduplicated training windows from eligible real pieces only.

Each class gets the same number of examples. Unique source works are reported
separately; crops/rescaling never become extra compositions. No validation/test
work is sampled. Transposition and tempo changes do not inflate example counts.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random

import numpy as np

from artifacts import write_json
from corpus import frozen_train, partition_id, work_id
from protocol import FEATURES, GENRES, MAX_NOTES, WINDOW, windows


def fingerprint(pieces):
    digest = hashlib.sha256()
    for p in sorted(pieces, key=lambda p: p['name']):
        value = [p['name'], work_id(p), partition_id(p), p['genre'], p['notes']]
        digest.update((json.dumps(value, separators=(',', ':')) + '\n').encode())
    return digest.hexdigest()


def build_bank(pieces, target, seed=20261110):
    if target < 1:
        raise ValueError('Examples per class must be positive')
    grouped = {g: [p for p in pieces if p['genre'] == g] for g in GENRES}
    if any(not ps for ps in grouped.values()):
        raise ValueError('Every class needs eligible real source pieces')
    rng = random.Random(seed)
    bank, origins, stats, seen = {}, {}, {}, set()
    for genre in GENRES:
        sources = list(grouped[genre])
        rng.shuffle(sources)
        rows, metadata, attempts = [], [], 0
        while len(rows) < target and attempts < max(1000, target * 100):
            piece = sources[attempts % len(sources)]
            original = piece['notes']
            canonical = attempts < len(sources)
            start = 0 if canonical else rng.randrange(max(1, len(original) - 31))
            size = MAX_NOTES if canonical else rng.choice((32, 40, 48, 64, 96, 160, MAX_NOTES))
            context = [list(n) for n in original[start:start + size]]
            # A cropped score still follows GenreModel.melody's leading-rest rule.
            while context and context[0][0] < 0:
                context.pop(0)
                start += 1
            scale = 1. if canonical else rng.choice((.5, 1., 1., 2.))
            for note in context:
                note[1] *= scale
            attempts += 1
            chunks = windows(context)
            if not chunks:
                continue
            index = rng.randrange(len(chunks))
            row = np.asarray(chunks[index], np.float32)
            actual = row[:, 4:9].sum(1) > 0  # Exclude zero-padding from note counts.
            if np.count_nonzero(actual & (row[:, 1] == 0)) < 16:
                continue
            sha = hashlib.sha256(row.tobytes()).hexdigest()
            if sha in seen:
                continue
            seen.add(sha)
            cropped = start != 0 or len(context) != min(len(original), MAX_NOTES)
            transforms = ['excerpt_crop'] if cropped else []
            if scale != 1.:
                transforms.append('rhythmic_rescaling')
            rows.append(row)
            metadata.append(dict(
                source_name=piece['name'], work_id=work_id(piece),
                group_id=partition_id(piece), genre=genre,
                kind='augmented_window' if transforms else 'source_window',
                transforms=transforms, context_start=start, context_events=len(context),
                rhythmic_scale=scale, window_index=index, feature_sha256=sha))
        if len(rows) != target:
            raise ValueError(f'{genre}: only {len(rows)} unique valid windows; cannot fill {target}')
        bank[genre] = np.stack(rows)
        origins[genre] = metadata
        counts = Counter(m['source_name'] for m in metadata)
        stats[genre] = dict(examples=len(rows), eligible_source_pieces=len(sources),
                            represented_source_pieces=len(counts),
                            represented_work_ids=len({m['work_id'] for m in metadata}),
                            represented_groups=len({m['group_id'] for m in metadata}),
                            source_windows=sum(m['kind'] == 'source_window' for m in metadata),
                            augmented_windows=sum(m['kind'] == 'augmented_window' for m in metadata),
                            examples_per_represented_source_min=min(counts.values()),
                            examples_per_represented_source_max=max(counts.values()),
                            rejected_attempts=attempts - len(rows))
        print(genre, stats[genre], flush=True)
    return bank, origins, stats


def save_bank(output, bank, origins, stats, pieces, fold, seed):
    output.mkdir(parents=True, exist_ok=True)
    arrays = output / 'features.npz'
    temporary = arrays.with_suffix('.tmp')
    with temporary.open('wb') as stream:
        np.savez_compressed(stream, **bank)
    temporary.replace(arrays)
    metadata = output / 'origins.jsonl'
    temporary = metadata.with_suffix('.tmp')
    with temporary.open('w') as stream:
        for genre in GENRES:
            for row, origin in enumerate(origins[genre]):
                stream.write(json.dumps(dict(row=row, **origin), separators=(',', ':')) + '\n')
    temporary.replace(metadata)
    manifest = dict(schema_version=1, fold=fold, seed=seed, classes=stats,
                    builder_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    source_fingerprint=fingerprint(pieces),
                    source_names=sorted(p['name'] for p in pieces),
                    examples_total=sum(len(v) for v in bank.values()),
                    feature_shape=[WINDOW, FEATURES], real_derived_only=True,
                    features_sha256=hashlib.sha256(arrays.read_bytes()).hexdigest(),
                    origins_sha256=hashlib.sha256(metadata.read_bytes()).hexdigest(),
                    unique_feature_windows=sum(len(v) for v in bank.values()),
                    note='Examples are windows, not independent compositions; holdouts are unaugmented.')
    write_json(output / 'manifest.json', manifest)
    return manifest


def load_bank(output, pieces, fold):
    """Refuse stale data, different folds, changed payloads and held-out origins."""
    output = Path(output)
    manifest = json.loads((output / 'manifest.json').read_text())
    if manifest['schema_version'] != 1 or manifest['fold'] != fold:
        raise ValueError('Balanced bank belongs to a different fold/schema')
    if manifest['source_fingerprint'] != fingerprint(pieces):
        raise ValueError('Balanced bank sources differ from eligible training works')
    for name, key in (('features.npz', 'features_sha256'), ('origins.jsonl', 'origins_sha256')):
        if hashlib.sha256((output / name).read_bytes()).hexdigest() != manifest[key]:
            raise ValueError(f'Balanced bank payload changed: {name}')
    by_name = {p['name']: p for p in pieces}
    counts = Counter()
    hashes = {g: [] for g in GENRES}
    with (output / 'origins.jsonl').open() as stream:
        for line in stream:
            origin = json.loads(line)
            p = by_name.get(origin['source_name'])
            if p is None or p['genre'] != origin['genre']:
                raise ValueError('Balanced bank has an ineligible/mislabelled origin')
            if work_id(p) != origin['work_id'] or partition_id(p) != origin['group_id']:
                raise ValueError('Balanced bank work/group identity changed')
            if origin['row'] != counts[origin['genre']]:
                raise ValueError('Balanced bank origin rows are out of order')
            hashes[origin['genre']].append(origin['feature_sha256'])
            counts[origin['genre']] += 1
    with np.load(output / 'features.npz', allow_pickle=False) as archive:
        if set(archive.files) != set(GENRES):
            raise ValueError('Balanced bank class set differs from model contract')
        bank = {g: archive[g].copy() for g in GENRES}
    for genre, rows in bank.items():
        n = manifest['classes'][genre]['examples']
        if rows.shape != (n, WINDOW, FEATURES) or rows.dtype != np.float32:
            raise ValueError('Balanced bank tensor contract changed')
        if counts[genre] != n or not np.isfinite(rows).all():
            raise ValueError('Balanced bank provenance/count/value mismatch')
        if any(hashlib.sha256(row.tobytes()).hexdigest() != expected
               for row, expected in zip(rows, hashes[genre])):
            raise ValueError('Balanced bank feature rows differ from their origins')
    if len({len(rows) for rows in bank.values()}) != 1:
        raise ValueError('Training bank is not balanced')
    all_hashes = [sha for values in hashes.values() for sha in values]
    if len(set(all_hashes)) != len(all_hashes):
        raise ValueError('Balanced bank contains duplicate feature windows')
    minor = bank['waltz'][:, -1, 21] > .5
    bank['minor_waltz'] = bank['waltz'][minor]
    return bank


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_root', type=Path)
    parser.add_argument('prepared', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--fold', choices=('all', '0', '1', '2', '3'), required=True)
    parser.add_argument('--per-class', type=int, help='Default: largest eligible class')
    parser.add_argument('--seed', type=int, default=20261110)
    args = parser.parse_args()
    pieces = []
    for name in ('pieces', 'more', 'pdmx'):
        pieces.extend(json.loads((args.data_root / 'out/genre' / f'{name}.json').read_text()))
    split = json.loads((args.prepared / 'legacy-split.json').read_text())
    additions = json.loads((args.prepared / 'additions.json').read_text())
    real = sorted(p['name'] for p in pieces if p['genre'] == 'kundiman' and p['name'] in split['train'])
    held_out = [] if args.fold == 'all' else [name for i, name in enumerate(real) if i % 4 == int(args.fold)]
    training = frozen_train(pieces, split, additions, held_out)
    target = (max(Counter(p['genre'] for p in training).values())
              if args.per_class is None else args.per_class)
    bank, origins, stats = build_bank(training, target, args.seed)
    manifest = save_bank(args.output, bank, origins, stats, training, args.fold, args.seed)
    load_bank(args.output, training, args.fold)
    print('Verified bank:', manifest['examples_total'], 'unique real-derived training windows', flush=True)


if __name__ == '__main__':
    main()

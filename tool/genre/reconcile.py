"""Prepare a separate conservative dataset version with shared inputs isolated.

Families share a work/group ID or an exact normalized model window at one of
the fixed 40/80/320-event prefixes. They are not asserted to be identical full
compositions. Conflicting labels are quarantined rather than guessed. The
highest-priority original evaluation partition wins; no row is moved there.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import struct

from artifacts import write_json
from corpus import assert_disjoint, frozen_train, training_corrections, work_id, partition_id
from protocol import windows

PRIORITY = {'train': 0, 'valid': 1, 'external_negative': 2, 'test': 3, 'fresh_test': 4}


def input_hashes(piece):
    hashes = set()
    for prefix in (40, 80, 320):
        for chunk in windows(piece['notes'][:prefix]):
            flat = [v for row in chunk for v in row]
            hashes.add(hashlib.sha256(struct.pack('<' + 'f' * len(flat), *flat)).hexdigest())
    return hashes


def reconcile(pieces, reviewed_groups=()):
    by_name = {p['name']: p for p in pieces}
    if len(by_name) != len(pieces):
        raise ValueError('Repeated source IDs require prior label quarantine')
    parent = {name: name for name in by_name}

    def find(name):
        while parent[name] != name:
            parent[name] = parent[parent[name]]
            name = parent[name]
        return name

    def join(a, b):
        a, b = find(a), find(b)
        parent[max(a, b)] = min(a, b)

    for group in reviewed_groups:
        members = group['members']
        if len(members) < 2 or len(set(members)) != len(members):
            raise ValueError('Reviewed work family needs distinct source IDs')
        if any(name not in by_name for name in members):
            raise ValueError('Reviewed work family refers to absent source IDs')
        for name in members[1:]:
            join(members[0], name)

    evidence = {}
    feature_owners = {}
    for piece in sorted(pieces, key=lambda p: p['name']):
        if piece['split'] not in PRIORITY:
            raise ValueError('Unknown partition')
        for identity in (('work', work_id(piece)), ('group', partition_id(piece))):
            if identity in evidence:
                join(piece['name'], evidence[identity])
            evidence[identity] = piece['name']
        for digest in input_hashes(piece):
            if digest in feature_owners:
                join(piece['name'], feature_owners[digest])
            feature_owners[digest] = piece['name']
    groups = defaultdict(list)
    for name in sorted(by_name):
        groups[find(name)].append(by_name[name])
    kept, families, removed = [], [], []
    for members in sorted(groups.values(), key=lambda ps: ps[0]['name']):
        names = sorted(p['name'] for p in members)
        family = 'input_family_' + hashlib.sha256('\n'.join(names).encode()).hexdigest()[:20]
        genres = {p['genre'] for p in members}
        chosen = None
        if len(genres) == 1:
            # Choose without consulting any model predictions or accuracy scores.
            chosen = min(members, key=lambda p: (-PRIORITY[p['split']],
                -sum(n[0] >= 0 for n in p['notes'][:320]), p['name']))
            kept.append(dict(chosen, group_id=family))
        if len(members) > 1:
            families.append(dict(group_id=family, members=names, labels=sorted(genres),
                                 partitions=sorted({p['split'] for p in members}),
                                 retained=chosen['name'] if chosen else None,
                                 reason='shared_input_family' if chosen else 'conflicting_labels'))
        for piece in members:
            if piece is not chosen:
                removed.append(dict(name=piece['name'], genre=piece['genre'],
                                    split=piece['split'], group_id=family,
                                    reason='shared_input_family' if chosen else 'conflicting_labels'))
    parts = {s: [p for p in kept if p['split'] == s] for s in PRIORITY}
    assert_disjoint(parts)
    # Independently verify the actual output's feature and identity boundaries.
    seen = {}
    for piece in kept:
        for digest in input_hashes(piece):
            if digest in seen:
                raise ValueError('Reconciled output still shares model input windows')
            seen[digest] = piece['name']
    counts = lambda ps: {s: dict(Counter(p['genre'] for p in ps if p['split'] == s)) for s in PRIORITY}
    return kept, dict(policy='shared_input_families_v1', prefixes=[40, 80, 320],
        reviewed_work_groups=list(reviewed_groups),
        priority=PRIORITY, original_counts=counts(pieces), retained_counts=counts(kept),
        original_rows=len(pieces), retained_rows=len(kept), families=families, excluded=removed,
        residual_exact_window_matches=0,
        limits=['Families can be shared phrases or arrangements, not necessarily identical compositions.',
                'Labels are never guessed; conflicting families are quarantined.',
                'Original source files and the legacy evaluation snapshot remain unchanged.',
                'No exact window matches does not prove complete composition independence.',
                'Fine-tuning cannot undo exposure already present in original pretrained weights.',
                'A separate untouched work-level test set remains necessary before promotion.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_root', type=Path)
    parser.add_argument('prepared', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--work-families', type=Path, help='Reviewed source/composer aliases, never title-only guesses')
    args = parser.parse_args()
    if args.output.resolve() == args.prepared.resolve():
        parser.error('Use a new output directory; preserve the frozen legacy snapshot')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('Output must be new/empty; reconciled datasets are versioned snapshots')
    originals = []
    expected = json.loads((args.prepared / 'input-hashes.json').read_text())
    for name in ('pieces', 'more', 'pdmx', 'extra'):
        path = args.data_root / 'out/genre' / f'{name}.json'
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected[name]:
            raise ValueError('Original data changed since preparation')
        if name != 'extra':
            originals += json.loads(path.read_text())
    split = json.loads((args.prepared / 'legacy-split.json').read_text())
    additions = json.loads((args.prepared / 'additions.json').read_text())
    corrections = training_corrections(args.prepared)
    training = frozen_train(originals, split, additions, corrections=corrections)
    evaluation = json.loads((args.prepared / 'baseline-corpus.json').read_text())
    pieces = [dict(p, split='train') for p in training]
    pieces += [p for p in evaluation if p['split'] != 'known_training']
    pieces += [p for p in additions if p['split'] == 'fresh_test']
    reviewed = []
    if args.work_families:
        manifest = json.loads(args.work_families.read_text())
        if manifest['schema_version'] != 1:
            raise ValueError('Unsupported work-family manifest schema')
        reviewed = manifest['groups']
    kept, report = reconcile(pieces, reviewed)
    kept_names = {p['name'] for p in kept}
    original_names = {p['name'] for p in originals}
    report['source_snapshot'] = str(args.prepared)
    report['source_snapshot_hashes'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                      for p in sorted(args.prepared.glob('*.json'))}
    report['input_hashes'] = expected
    report['builder_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report['work_families_sha256'] = hashlib.sha256(args.work_families.read_bytes()).hexdigest() if args.work_families else None
    output_split = {s: [p['name'] for p in kept if p['split'] == s and p['name'] in original_names]
                    for s in ('train', 'valid', 'test')}
    output_additions = [p for p in additions if p['name'] in kept_names]
    output_eval = [p for p in evaluation if p['name'] in kept_names]
    kept_training = {p['name'] for p in kept if p['split'] == 'train'}
    output_corrections = [p for p in corrections if p['name'] in kept_training]
    # Training corrections remain training-only; diagnostic/evaluation notes stay frozen.
    args.output.mkdir(parents=True, exist_ok=True)
    for name, value in (('legacy-split.json', output_split), ('additions.json', output_additions),
                        ('baseline-corpus.json', output_eval), ('input-hashes.json', expected),
                        ('training-corrections.json', output_corrections), ('reconciled-corpus.json', kept)):
        write_json(args.output / name, value, compact=True)
    for name in ('curation.json', 'quarantine.json'):
        write_json(args.output / name, json.loads((args.prepared / name).read_text()), compact=True)
    report['output_hashes'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(args.output.glob('*.json'))}
    write_json(args.output / 'reconciliation.json', report)
    print('Retained:', report['retained_counts'], flush=True)
    print('Families:', len(report['families']), 'excluded:', len(report['excluded']),
          'remaining exact model-window matches:', report['residual_exact_window_matches'], flush=True)


if __name__ == '__main__':
    main()

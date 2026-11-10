"""Explain frozen genre errors without moving or relabelling evaluation works."""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import struct

from artifacts import write_json
from corpus import frozen_train, training_corrections
from protocol import GENRES, key_of, rule_label, windows


def classification(rows, field):
    """Raw four-class metrics; keep app fallback decisions separate."""
    matrix = [[0] * len(GENRES) for _ in GENRES]
    for row in rows:
        probabilities = row[field]
        if probabilities is None:
            raise ValueError('Raw metrics require probabilities for every piece')
        actual = GENRES.index(row['expected'])
        predicted = max(range(len(GENRES)), key=lambda i: probabilities[i])
        matrix[actual][predicted] += 1
    classes = {}
    for i, genre in enumerate(GENRES):
        support, predicted = sum(matrix[i]), sum(r[i] for r in matrix)
        tp = matrix[i][i]
        precision = tp / predicted if predicted else 0.
        recall = tp / support if support else 0.
        classes[genre] = dict(support=support, precision=precision, recall=recall,
                             f1=2 * precision * recall / (precision + recall)
                             if precision + recall else 0.)
    return dict(pieces=len(rows), order=list(GENRES), confusion=matrix, classes=classes,
                accuracy=sum(matrix[i][i] for i in range(len(GENRES))) / len(rows)
                if rows else None,
                macro_f1=sum(c['f1'] for c in classes.values()) / len(GENRES))


def explain(probabilities, notes):
    raw = GENRES[max(range(len(GENRES)), key=lambda i: probabilities[i])]
    if raw != 'other' and max(probabilities) >= .7:
        return 'confident_model'
    rule = rule_label(notes)
    if rule == 'kundiman' and probabilities[1] < .4:
        return 'kundiman_rule_vetoed'
    return 'rule_fallback'


def summarize(report, pieces):
    by_name = {p['name']: p for p in pieces}
    groups = defaultdict(list)
    errors, unique = [], set()
    for row in report:
        identity = (row['split'], row['name'], row['prefix'])
        if identity in unique:
            raise ValueError('Repeated piece/prefix would inflate audit counts')
        unique.add(identity)
        piece = by_name[row['name']]
        if row['expected'] != piece['genre']:
            raise ValueError('Report labels disagree with frozen corpus')
        groups[(row['split'], row['prefix'])].append(row)
        for model in ('baseline', 'candidate'):
            false_k = row['expected'] != 'kundiman' and row[model + '_app'] == 'kundiman'
            missed_k = row['expected'] == 'kundiman' and row[model + '_app'] != 'kundiman'
            if not (false_k or missed_k):
                continue
            notes = piece['notes'][:row['prefix']]
            probabilities = row[model]
            errors.append(dict(name=row['name'], title=piece.get('title'),
                               source=piece['source'], split=row['split'],
                               prefix=row['prefix'], model=model, expected=row['expected'],
                               app=row[model + '_app'], probabilities=probabilities,
                               kind='false_kundiman' if false_k else 'missed_kundiman',
                               raw=GENRES[max(range(4), key=lambda i: probabilities[i])],
                               decision=explain(probabilities, notes),
                               events=len(notes), sounding=sum(n[0] >= 0 for n in notes),
                               meter_events=dict(Counter(str(n[3]) for n in notes)),
                               estimated_key=list(key_of(notes)), rule=rule_label(notes)))
    summaries = []
    for (split, prefix), rows in sorted(groups.items()):
        values = {}
        for model in ('baseline', 'candidate'):
            values[model] = dict(raw=classification(rows, model),
                app_correct={g: sum(r[model + '_app'] == g for r in rows if r['expected'] == g)
                             for g in GENRES if g != 'other'},
                false_kundiman=sum(r['expected'] != 'kundiman' and
                                  r[model + '_app'] == 'kundiman' for r in rows))
        summaries.append(dict(split=split, prefix=prefix, **values))
    return dict(summaries=summaries, kundiman_errors=errors,
                limits=['Rows are score excerpts at fixed prefixes, not independent windows.',
                        'Training diagnostics are not generalization evidence.',
                        'Raw Other predictions differ from the app, which falls back to genre rules.',
                        'Auditing test errors makes that test a reused development benchmark; future promotion needs untouched works.',
                        'No labels or partitions are changed by this audit.'])


def feature_overlaps(training, evaluation):
    """Find exact normalized input matches, without assuming composition identity."""
    indexed = defaultdict(set)
    def hashes(piece):
        for chunk in windows(piece['notes']):
            flat = [v for row in chunk for v in row]
            yield hashlib.sha256(struct.pack('<' + 'f' * len(flat), *flat)).hexdigest()
    for piece in training:
        for digest in hashes(piece):
            indexed[digest].add((piece['name'], piece['genre']))
    matches = []
    for piece in evaluation:
        found = set()
        for digest in hashes(piece):
            found.update(indexed.get(digest, ()))
        if found:
            matches.append(dict(name=piece['name'], split=piece['split'], genre=piece['genre'],
                                training_matches=[dict(name=n, genre=g) for n, g in sorted(found)]))
    return dict(matches=matches, evaluation_pieces_with_matches=len(matches),
                limit='Exact normalized input matches flag possible duplicates or shared phrases; no automatic relabelling or repartitioning. Non-matches do not establish composition independence.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prepared', type=Path)
    parser.add_argument('paired_report', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--data-root', type=Path, help='Also check train/evaluation normalized feature overlap')
    args = parser.parse_args()
    pieces = json.loads((args.prepared / 'baseline-corpus.json').read_text())
    pieces += json.loads((args.prepared / 'additions.json').read_text())
    report = json.loads(args.paired_report.read_text())
    result = summarize(report['pieces'], pieces)
    if args.data_root:
        originals = []
        for name in ('pieces', 'more', 'pdmx'):
            originals += json.loads((args.data_root / 'out/genre' / f'{name}.json').read_text())
        split = json.loads((args.prepared / 'legacy-split.json').read_text())
        additions = json.loads((args.prepared / 'additions.json').read_text())
        training = frozen_train(originals, split, additions, corrections=training_corrections(args.prepared))
        result['feature_overlap'] = feature_overlaps(training, [p for p in pieces
            if p['split'] not in ('known_training', 'new_train')])
    result['paired_report_sha256'] = hashlib.sha256(args.paired_report.read_bytes()).hexdigest()
    write_json(args.output, result)
    print(f"Audited {len(report['pieces'])} frozen piece/prefix comparisons")


if __name__ == '__main__':
    main()

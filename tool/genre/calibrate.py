"""Choose a class calibration using validation works only, then evaluate once.

The calibration acts on EACH window, before the app's probability average.
The .7/.4 display thresholds are unchanged. No test result selects the scale.
"""

import argparse
import json
from pathlib import Path

import torch

from protocol import app_label
from artifacts import write_json
from train import Calibrated, load_model, paired_report, predict_many


def metrics(rows, field):
    result = {}
    for prefix in (40, 80, 320):
        selected = [r for r in rows if r['prefix'] == prefix]
        result[prefix] = dict(
            kundiman=sum(r[field + '_app'] == 'kundiman' for r in selected
                         if r['expected'] == 'kundiman'),
            false_kundiman=sum(r[field + '_app'] == 'kundiman' for r in selected
                               if r['expected'] != 'kundiman'),
            negative_correct=sum(r[field + '_app'] == r['expected'] for r in selected
                                 if r['expected'] in ('waltz', 'jazz')))
    return result


def acceptable(before, after):
    return all(after[p]['kundiman'] >= before[p]['kundiman']
               and after[p]['false_kundiman'] <= before[p]['false_kundiman']
               and after[p]['negative_correct'] >= before[p]['negative_correct']
               for p in before)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_root', type=Path)
    parser.add_argument('experiment', type=Path)
    parser.add_argument('--fold', choices=('all', '0', '1', '2', '3'), required=True)
    args = parser.parse_args()
    torch.set_num_threads(2)
    output = args.experiment / f'candidate_{args.fold}'
    checkpoint = output / 'genre_lstm.pt'
    if checkpoint.with_suffix('.calibration.json').exists():
        raise ValueError('Calibration already frozen; use a new experiment directory')
    candidate = load_model(checkpoint)
    baseline = load_model(args.data_root / f'out/genre_cv_{args.fold}/genre_lstm.pt')
    corpus = json.loads((args.experiment / 'baseline-corpus.json').read_text())
    valid = [p for p in corpus if p['split'] == 'valid']
    report = paired_report(baseline, candidate, valid)
    before = metrics(report, 'baseline')
    attempts, chosen = [], None
    # Largest admissible scale preserves as much Kundiman probability as possible.
    for scale in (1., .75, .5, .25, .125):
        model = Calibrated(candidate, scale).eval()
        probabilities = predict_many(model, [p['notes'][:n] for p in valid for n in (40, 80, 320)])
        for row, probs, (p, prefix) in zip(report, probabilities,
                                         [(p, n) for p in valid for n in (40, 80, 320)]):
            row['candidate'] = probs
            row['candidate_app'] = app_label(probs, p['notes'][:prefix])
        after = metrics(report, 'candidate')
        attempts.append(dict(scale=scale, metrics=after))
        print(f'fold {args.fold}, validation scale={scale}: {after}', flush=True)
        if acceptable(before, after):
            chosen = scale
            break
    decision = dict(kundiman_scale=chosen, validation_baseline=before,
                    attempts=attempts, selection='validation only; largest admissible fixed-grid scale')
    write_json(output / 'calibration-decision.json', decision)
    if chosen is None:
        print('No calibration meets validation constraints; candidate rejected', flush=True)
        return
    write_json(checkpoint.with_suffix('.calibration.json'), decision)
    # Evaluation happens after freezing the validation-only choice.
    if args.fold == 'all':
        evaluation = corpus + json.loads((args.experiment / 'additions.json').read_text())
    else:
        split = json.loads((args.experiment / 'legacy-split.json').read_text())
        real_ids = sorted(p['name'] for p in corpus
                          if p['genre'] == 'kundiman'
                          and p['name'] in split['train'])
        held_out = [name for i, name in enumerate(real_ids) if i % 4 == int(args.fold)]
        evaluation = [dict(p, split='cv_test') for p in corpus if p['name'] in held_out]
    calibrated = paired_report(baseline, Calibrated(candidate, chosen).eval(), evaluation)
    write_json(output / 'calibrated-report.json', dict(scale=chosen, pieces=calibrated))


if __name__ == '__main__':
    main()

"""CPU fine-tuning experiment using the existing data project's checkpoints.

Does not install packages, alter the original data project, or promote a model.
All passages of one work follow its frozen original fold. Test pieces are never
used for sampling or checkpoint selection. See README.md for reproduction.
"""

import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import random
import sys

import numpy as np
import torch

from corpus import frozen_train, training_corrections, verify_reconciliation
from artifacts import write_json
from protocol import FEATURES, GENRES, app_label, key_of, windows


class Net(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.lstm = torch.nn.LSTM(FEATURES, 64, num_layers=2, batch_first=True, dropout=.2)
        self.head = torch.nn.Linear(64, len(GENRES))

    def logits(self, x):
        out, _ = self.lstm(x)
        return self.head(out[:, -1])

    def forward(self, x):
        return torch.softmax(self.logits(x), -1)


class Mean(torch.nn.Module):
    def __init__(self, count=4):
        super().__init__()
        self.nets = torch.nn.ModuleList([Net() for _ in range(count)])

    def forward(self, x):
        return sum(n(x) for n in self.nets) / len(self.nets)


class Calibrated(torch.nn.Module):
    def __init__(self, model, scale):
        super().__init__()
        self.model = model
        self.register_buffer('scale', torch.tensor([1., scale, 1., 1.]))

    def forward(self, x):
        probabilities = self.model(x) * self.scale
        return probabilities / probabilities.sum(-1, keepdim=True)


def load_model(path):
    path = Path(path)
    model = Mean()
    model.load_state_dict(torch.load(path, map_location='cpu', weights_only=True))
    calibration = path.with_suffix('.calibration.json')
    if calibration.exists():
        model = Calibrated(model, json.loads(calibration.read_text())['kundiman_scale'])
    return model.eval()


def predict(model, notes):
    chunks = windows(notes)
    if not chunks:
        return None
    with torch.inference_mode():
        return model(torch.tensor(np.asarray(chunks, np.float32))).mean(0).tolist()


def bank_for(pieces, synthetic, rng):
    """Cache realistic visible contexts; recompute key before taking a window.

    Uniform duration scaling is applied to every class, never just Kundiman.
    It represents equivalent notation at different rhythmic resolutions.
    """
    banks = defaultdict(list)
    for piece in pieces:
        notes = piece['notes']
        repeats = 96 if piece['genre'] == 'kundiman' else 5
        minor_waltz = piece['genre'] == 'waltz' and key_of(notes[:320])[1]
        for index in range(repeats):
            length = rng.choice((24, 40, 64, 96, 160, 320))
            start = 0 if index < 3 else rng.randrange(max(1, len(notes) - 23))
            context = [list(n) for n in notes[start:start + length]]
            scale = rng.choice((.5, 1., 1., 1., 2.))
            for n in context:
                n[1] *= scale
            chunks = windows(context)
            if not chunks:
                continue
            chunk = np.asarray(rng.choice(chunks), np.float32)
            banks[piece['genre']].append(chunk)
            if minor_waltz:
                banks['minor_waltz'].append(chunk)
    for notes in synthetic:
        start = rng.randrange(max(1, len(notes) - 23))
        context = [list(n) for n in notes[start:start + rng.randint(24, 160)]]
        scale = rng.choice((.5, 1., 1., 1., 2.))
        for n in context:
            n[1] *= scale
        chunks = windows(context)
        if chunks:
            banks['synthetic'].append(np.asarray(rng.choice(chunks), np.float32))
    return {k: np.stack(v) for k, v in banks.items()}


def hard_negative_bank(baseline, bank):
    """Mine only eligible training windows; no evaluation predictions enter here."""
    bank = dict(bank)
    counts = {}
    for genre in ('waltz', 'jazz', 'other'):
        rows = bank[genre]
        with torch.no_grad():
            scores = np.concatenate([baseline(torch.from_numpy(rows[i:i + 128]))[:, 1].numpy()
                                     for i in range(0, len(rows), 128)])
        count = max(1, math.ceil(len(rows) * .1))
        selected = np.argsort(scores, kind='stable')[-count:]
        bank['hard_' + genre] = rows[selected]
        counts[genre] = dict(windows=count, lowest_kundiman_probability=float(scores[selected[0]]))
    return bank, counts


def tune(baseline, bank, steps, conservative=False):
    candidate = Mean()
    candidate.load_state_dict(baseline.state_dict())
    for i, seed in enumerate((7, 1, 2, 3)):
        rng = random.Random(seed)
        torch.manual_seed(seed)
        net, teacher = candidate.nets[i].train(), baseline.nets[i].eval()
        opt = torch.optim.Adam(net.parameters(), lr=1e-5 if conservative else 1e-4)
        for step in range(steps):
            labels = [rng.randrange(4) for _ in range(64)]
            rows = []
            for label in labels:
                group = GENRES[label]
                if conservative and group != 'kundiman' and rng.random() < .5:
                    group = 'hard_' + group
                elif group == 'kundiman' and 'synthetic' in bank and rng.random() < .3:
                    group = 'synthetic'
                elif group == 'waltz' and len(bank.get('minor_waltz', ())) and rng.random() < .5:
                    group = 'minor_waltz'
                rows.append(bank[group][rng.randrange(len(bank[group]))])
            x = torch.from_numpy(np.stack(rows))
            y = torch.tensor(labels)
            logits = net.logits(x)
            loss = torch.nn.functional.cross_entropy(logits, y)
            # Retain the baseline's distinctions among the abundant negatives.
            negatives = y != 1
            with torch.no_grad():
                targets = teacher(x[negatives])
            loss += (2. if conservative else .5) * torch.nn.functional.kl_div(
                logits[negatives].log_softmax(-1), targets, reduction='batchmean')
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(net.parameters(), 1.)
            opt.step()
        print(f'seed {seed}: {steps} steps, loss {loss.item():.4f}', flush=True)
        net.eval()
    return candidate.eval()


def predict_many(model, requests):
    """Bounded batches avoid both slow single-window calls and a huge tensor."""
    sums = np.zeros((len(requests), 4), np.float64)
    counts = np.zeros(len(requests), np.int32)
    batch, owners = [], []

    def flush():
        if not batch:
            return
        with torch.inference_mode():
            probabilities = model(torch.from_numpy(np.asarray(batch, np.float32))).numpy()
        for owner, probabilities in zip(owners, probabilities):
            sums[owner] += probabilities
            counts[owner] += 1
        batch.clear()
        owners.clear()

    for owner, notes in enumerate(requests):
        for chunk in windows(notes):
            batch.append(chunk)
            owners.append(owner)
            if len(batch) == 64:
                flush()
    flush()
    return [(sums[i] / counts[i]).tolist() if counts[i] else None
            for i in range(len(requests))]


def paired_report(baseline, candidate, pieces):
    requests = [(p, prefix) for p in pieces for prefix in (40, 80, 320)]
    notes = [p['notes'][:prefix] for p, prefix in requests]
    before, after = predict_many(baseline, notes), predict_many(candidate, notes)
    rows = []
    for (p, prefix), melody, old, new in zip(requests, notes, before, after):
        rows.append(dict(name=p['name'], expected=p['genre'], split=p.get('split'),
                         prefix=prefix, baseline=old, candidate=new,
                         baseline_app=app_label(old, melody),
                         candidate_app=app_label(new, melody)))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_root', type=Path)
    parser.add_argument('experiment', type=Path)
    parser.add_argument('--steps', type=int, default=200)
    parser.add_argument('--fold', choices=('all', '0', '1', '2', '3'), required=True)
    parser.add_argument('--bank-dir', type=Path,
                        help='Use a verified, balanced real-derived bank instead of synthetic sampling')
    parser.add_argument('--conservative', action='store_true',
                        help='Fixed 1e-5 LR, 2x distillation, 50%% hardest-decile negative sampling')
    args = parser.parse_args()
    if args.conservative and not args.bank_dir:
        parser.error('--conservative requires a verified --bank-dir')
    torch.set_num_threads(2)
    sys.path.insert(0, str(args.data_root / 'scripts'))
    import genre_train as legacy
    import kundiman_gen

    root = args.experiment
    verify_reconciliation(root, args.data_root)
    pieces = []
    for name in ('pieces', 'more', 'pdmx'):
        pieces.extend(json.loads((args.data_root / 'out/genre' / f'{name}.json').read_text()))
    split = json.loads((root / 'legacy-split.json').read_text())
    additions = json.loads((root / 'additions.json').read_text())
    real_ids = sorted(p['name'] for p in pieces
                      if p['genre'] == 'kundiman' and p['name'] in split['train'])
    held_out = [] if args.fold == 'all' else [name for i, name in enumerate(real_ids)
                                             if i % 4 == int(args.fold)]
    corrections = training_corrections(root)
    training = frozen_train(pieces, split, additions, held_out, corrections)
    print(f'fold={args.fold}, training={len(training)}, held_out={held_out}', flush=True)
    if args.bank_dir:
        from balanced import load_bank, bank_exclusions
        bank = load_bank(args.bank_dir, training, args.fold, bank_exclusions(root, held_out))
    else:
        rng = random.Random(20261109)
        synthetic = [kundiman_gen.kundiman(rng) for _ in range(1400)]
        synthetic += [legacy.trait_kundiman(rng) for _ in range(600)]
        bank = bank_for(training, synthetic, rng)
    print({key: len(value) for key, value in bank.items()}, flush=True)
    checkpoint = args.data_root / f'out/genre_cv_{args.fold}/genre_lstm.pt'
    baseline = load_model(checkpoint)
    hard_negatives = None
    if args.conservative:
        bank, hard_negatives = hard_negative_bank(baseline, bank)
        print('Training-only hard negatives:', hard_negatives, flush=True)
    candidate = tune(baseline, bank, args.steps, args.conservative)
    output = root / f'candidate_{args.fold}'
    output.mkdir(exist_ok=True)
    torch.save(candidate.state_dict(), output / 'genre_lstm.pt')
    report = dict(steps=args.steps, fold=args.fold, seeds=[7, 1, 2, 3],
                  lr=1e-5 if args.conservative else 1e-4,
                  negative_distillation_weight=2. if args.conservative else .5,
                  hard_negatives=hard_negatives,
                  real_kundiman_share=1. if args.bank_dir else .7,
                  synthetic_kundiman_share=0. if args.bank_dir else .3,
                  bank_dir=str(args.bank_dir) if args.bank_dir else None,
                  checkpoint_sha256=hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
                  reconciliation_sha256=hashlib.sha256((root / 'reconciliation.json').read_bytes()).hexdigest()
                  if (root / 'reconciliation.json').exists() else None,
                  training_corrections=[p['name'] for p in training if 'correction_provenance' in p],
                  held_out=held_out, train_names=[p['name'] for p in training])
    write_json(output / 'training-manifest.json', report)
    # Evaluation occurs only after the fixed training schedule has finished.
    evaluation = [dict(p, split='cv_test') for p in pieces if p['name'] in held_out]
    if args.fold == 'all':
        evaluation = json.loads((root / 'baseline-corpus.json').read_text()) + additions
    report['pieces'] = paired_report(baseline, candidate, evaluation)
    write_json(output / 'paired-report.json', report)
    print(f'Finished {output}', flush=True)


if __name__ == '__main__':
    main()

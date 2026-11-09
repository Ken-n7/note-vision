"""Export an experimental checkpoint and check Torch/LiteRT probability parity."""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch

from benchmark import Predictor
from artifacts import write_json
from protocol import windows
from train import load_model


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkpoint', type=Path)
    parser.add_argument('corpus', type=Path)
    args = parser.parse_args()
    torch.set_num_threads(2)
    import litert_torch

    net = load_model(args.checkpoint)
    sample = torch.zeros((1, 64, 22), dtype=torch.float32)
    output = args.checkpoint.with_suffix('.tflite')
    model = litert_torch.convert(net, (sample,))
    model.export(str(output))
    predictor = Predictor(output)
    maximum, checked = 0., 0
    for piece in json.loads(args.corpus.read_text())[:32]:
        for prefix in (16, 40, 80, 320):
            chunks = windows(piece['notes'][:prefix])
            if not chunks:
                continue
            with torch.inference_mode():
                expected = net(torch.tensor(np.asarray(chunks, np.float32))).mean(0).numpy()
            actual = predictor(piece['notes'][:prefix])
            maximum = max(maximum, float(np.max(np.abs(expected - actual))))
            checked += 1
    if not checked or maximum >= 1e-4:
        raise ValueError(f'Export parity failed: {checked} inputs, max error {maximum}')
    report = dict(checked=checked, max_absolute_error=maximum,
                  sha256=hashlib.sha256(output.read_bytes()).hexdigest())
    write_json(output.with_suffix('.parity.json'), report)
    print(report, flush=True)


if __name__ == '__main__':
    main()

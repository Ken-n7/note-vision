"""Evaluate a TFLite genre model with the app's exact windows and label rules.

The input is a JSON list of {name, genre, source, notes, split?, work_id?}.
Results are per score, not per overlapping window. Training/validation items
must be identified as such: they are diagnostics, never held-out evidence.
"""

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

import numpy as np
from ai_edge_litert.interpreter import Interpreter

from protocol import GENRES, app_label, windows
from artifacts import write_json


class Predictor:
    def __init__(self, model):
        self.interpreter = Interpreter(model_path=str(model), num_threads=2)
        self.interpreter.allocate_tensors()
        self.input = self.interpreter.get_input_details()[0]
        self.output = self.interpreter.get_output_details()[0]
        if list(self.input["shape"]) != [1, 64, 22] or list(self.output["shape"]) != [1, 4]:
            raise ValueError("Incompatible mobile genre tensor contract")

    def __call__(self, notes):
        chunks = windows(notes)
        if not chunks:
            return None
        probabilities = []
        for chunk in chunks:
            self.interpreter.set_tensor(self.input["index"], np.asarray([chunk], np.float32))
            self.interpreter.invoke()
            probabilities.append(self.interpreter.get_tensor(self.output["index"])[0].copy())
        return np.mean(probabilities, axis=0).astype(float).tolist()


def evaluate(model, corpus, prefixes=(40, 80, 320)):
    predict = Predictor(model)
    results, groups = [], defaultdict(list)
    for piece in corpus:
        if piece["genre"] not in GENRES:
            raise ValueError(f"Unknown genre: {piece['genre']}")
        for prefix in prefixes:
            notes = piece["notes"][:prefix]
            probabilities = predict(notes)
            raw = GENRES[max(range(4), key=lambda i: probabilities[i])] if probabilities else None
            row = {
                "name": piece["name"], "work_id": piece.get("work_id", piece["name"]),
                "source": piece["source"], "split": piece.get("split", "unassigned"),
                "expected": piece["genre"], "prefix": prefix,
                "probabilities": probabilities, "raw": raw, "app": app_label(probabilities, notes),
            }
            results.append(row)
            groups[(row["split"], prefix, row["expected"])].append(row)
    summary = []
    for (split, prefix, genre), rows in sorted(groups.items()):
        summary.append({
            "split": split, "prefix": prefix, "genre": genre, "pieces": len(rows),
            "raw_correct": sum(r["raw"] == genre for r in rows),
            "app_correct": None if genre == "other" else sum(r["app"] == genre for r in rows),
            "app_called_kundiman": sum(r["app"] == "kundiman" for r in rows),
        })
    return {
        "model_sha256": hashlib.sha256(Path(model).read_bytes()).hexdigest(),
        "protocol": {"window": 64, "stride": 32, "max_notes": 320,
                     "min_notes": 16, "confidence": .7, "rule_kundiman": .4},
        "summary": summary, "pieces": results,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("corpus", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    corpus = json.loads(args.corpus.read_text())
    report = evaluate(args.model, corpus)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.output, report)
    for row in report["summary"]:
        print(row, flush=True)

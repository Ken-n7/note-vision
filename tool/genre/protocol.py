"""Frozen mobile genre inference contract; no detector or label-policy changes."""

import math

GENRES = ("waltz", "kundiman", "jazz", "other")
WINDOW = 64
MAX_NOTES = 320
FEATURES = 22
MAJOR = (6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88)
MINOR = (6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17)


def key_of(notes):
    histogram = [0.0] * 12
    for midi, length, _, _ in notes:
        if midi >= 0:
            histogram[int(midi) % 12] += length
    best, key = -2.0, (0, False)
    for minor, profile in ((False, MAJOR), (True, MINOR)):
        for tonic in range(12):
            rotated = [profile[(pc - tonic) % 12] for pc in range(12)]
            ma, mb = sum(histogram) / 12, sum(rotated) / 12
            cov = sum((a - ma) * (b - mb) for a, b in zip(histogram, rotated))
            va = sum((a - ma) ** 2 for a in histogram)
            vb = sum((b - mb) ** 2 for b in rotated)
            corr = cov / math.sqrt(va * vb) if va > 0 and vb > 0 else 0.0
            if corr > best:
                best, key = corr, (tonic, minor)
    return key


def features(notes):
    rows, previous = [], None
    tonic, minor = key_of(notes)
    for midi, length, place, beats in notes:
        midi = int(midi)
        row = [0.0] * FEATURES
        if midi >= 0:
            if previous is not None:
                row[0] = max(-1.0, min(1.0, (midi - previous) / 12))
            previous = midi
            row[9 + (midi - tonic) % 12] = 1.0
        else:
            row[1] = 1.0
        row[2] = math.log2(max(length, 1 / 16)) / 2
        row[3] = float(place)
        meters = (2, 3, 4, 6)
        row[4 + (meters.index(int(beats)) if int(beats) in meters else 4)] = 1.0
        row[21] = float(minor)
        rows.append(row)
    return rows


def windows(notes):
    """Cap the song BEFORE extracting its key, exactly as GenreModel.predict."""
    rows = features(notes[:MAX_NOTES])
    if sum(row[1] == 0 for row in rows) < 16:
        return []
    return [
        [[0.0] * FEATURES for _ in range(max(0, WINDOW - end))]
        + rows[max(0, end - WINDOW):end]
        for end in range(min(WINDOW, len(rows)), len(rows) + 1, WINDOW // 2)
    ]


def rule_label(notes):
    """Rules use the full melody, whereas model input is capped at 320."""
    sounding = [n for n in notes if n[0] >= 0]
    if not sounding:
        return None
    meters = {}
    for _, length, _, beats in sounding:
        meters[beats] = meters.get(beats, 0) + length
    beats = max(meters, key=meters.get)
    if beats not in (3, 6, 9):
        return "jazz"
    return "kundiman" if key_of(sounding[:max(16, len(sounding) // 2)])[1] else "waltz"


def app_label(probabilities, notes):
    if probabilities is not None:
        best = max(range(len(GENRES)), key=lambda i: probabilities[i])
        if GENRES[best] != "other" and probabilities[best] >= .7:
            return GENRES[best]
    label = rule_label(notes)
    if label == "kundiman" and probabilities is not None and probabilities[1] < .4:
        return "waltz"
    return label

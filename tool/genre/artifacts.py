"""Commit JSON outputs atomically so interrupted runs cannot look complete."""

import json
from pathlib import Path


def write_json(path, value, compact=False):
    path = Path(path)
    temporary = path.with_name(path.name + '.tmp')
    try:
        text = (json.dumps(value, separators=(',', ':')) if compact
                else json.dumps(value, indent=2))
        temporary.write_text(text + '\n')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)

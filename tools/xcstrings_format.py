#!/usr/bin/env python3
"""Read/write Localizable.xcstrings in Xcode's own serialization.

Xcode writes `"key" : value` (space before the colon), empty objects as a brace
pair around a blank line, and no trailing newline. `json.dumps` writes none of
those, so a script that round-trips the catalog with plain json produces a
~35k-line cosmetic diff on top of whatever it actually changed — and xcodebuild
does not normalize it back. Writing through `dump`/`write` keeps the diff to the
entries that really changed.

Key order is preserved as read, never sorted: Xcode's ordering is its own
collation (`"#%lld"` and `"%"` do not sort where Python puts them), so the file's
existing order is the only safe one. New top-level keys therefore land wherever
they are inserted — let Xcode re-sort those on its next write.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

_EMPTY_OBJECT_RE = re.compile(r'^(?P<indent>[ ]*)(?P<head>.*): \{\}(?P<tail>,?)$', re.M)


def dumps(data: dict) -> str:
    text = json.dumps(data, indent=2, ensure_ascii=False)
    text = _EMPTY_OBJECT_RE.sub(
        lambda m: f'{m["indent"]}{m["head"]} : {{\n\n{m["indent"]}}}{m["tail"]}',
        text,
    )
    return text.replace('": ', '" : ')


def load(path: Path) -> dict:
    return json.loads(Path(path).read_text())


def write(path: Path, data: dict) -> None:
    Path(path).write_text(dumps(data))

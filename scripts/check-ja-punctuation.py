#!/usr/bin/env python3
"""Report Japanese 、。 in Markdown; repository docs use ，． instead."""

import re
import sys
from pathlib import Path

FENCE = re.compile(r"^\s*(```|~~~)")
# Inline code and quoted UI text keep their original punctuation.
PROTECTED = re.compile(r"`[^`]*`|「[^」]*」")
PUNCTUATION = re.compile("[、。]")


def violations(path: Path) -> list[str]:
    found = []
    in_fence = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence and PUNCTUATION.search(PROTECTED.sub("", line)):
            found.append(f"{path}:{number}: 「、。」を「，．」にする: {line.strip()}")
    return found


def main() -> int:
    found = [v for name in sys.argv[1:] for v in violations(Path(name))]
    print("\n".join(found), end="\n" if found else "")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())

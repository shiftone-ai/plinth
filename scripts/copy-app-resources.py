#!/usr/bin/env python3
"""Copy every resource bundle in the app target's Swift package dependency graph."""

import json
import shutil
import sys
from pathlib import Path


def required_bundles(manifest: dict, executable: str) -> list[str]:
    targets = {target["name"]: target for target in manifest["targets"]}
    pending = [executable]
    visited: set[str] = set()
    resources: list[str] = []
    while pending:
        name = pending.pop()
        if name in visited:
            continue
        visited.add(name)
        target = targets[name]
        if target.get("resources"):
            resources.append(f"{manifest['name']}_{name}.bundle")
        for dependency in target.get("dependencies", []):
            name_and_condition = dependency.get("byName")
            if name_and_condition and name_and_condition[0] in targets:
                pending.append(name_and_condition[0])
    return sorted(resources)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: copy-app-resources.py <products> <app-resources>", file=sys.stderr)
        return 2
    products, destination = map(Path, sys.argv[1:])
    manifest = json.load(sys.stdin)
    names = required_bundles(manifest, "Plinth")
    for name in names:
        if not (products / name).is_dir():
            print(f"Missing built resource bundle: {name}", file=sys.stderr)
            return 1

    destination.mkdir(parents=True, exist_ok=True)
    for stale in destination.glob(f"{manifest['name']}_*.bundle"):
        if stale.is_dir():
            shutil.rmtree(stale)
    for name in names:
        shutil.copytree(products / name, destination / name)
    print(f"Copied {len(names)} app resource bundles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

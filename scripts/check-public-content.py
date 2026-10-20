"""Reject contact addresses and internal service notes in this public repository."""

import re
import subprocess
import sys
from pathlib import Path

EMAIL = re.compile(r"(?<![\w.+-])[\w.+-]+@([\w.-]+\.[a-zA-Z]{2,})")
SERVICE_NOTES = re.compile(
    "|".join(
        (
            "Google " + "Workspace",
            "Google " + "Groups",
            "Google " + "Vault",
            "G" + "mail",
            "問い合わせ" + "グループ",
            "保留中の" + "メッセージ",
        )
    ),
    re.IGNORECASE,
)
EXAMPLE_DOMAINS = {"example.com", "example.org", "example.net"}
SELF = Path(__file__).resolve()


def tracked_paths(staged: bool) -> list[Path]:
    command = (
        ["git", "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMRT"]
        if staged
        else ["git", "ls-files", "-z"]
    )
    result = subprocess.run(command, check=True, capture_output=True)
    return [Path(name.decode()) for name in result.stdout.split(b"\0") if name]


def check(paths: list[Path], staged: bool = False) -> int:
    failed = False
    for path in paths:
        if (not staged and not path.is_file()) or path.resolve() == SELF:
            continue
        try:
            data = (
                subprocess.run(["git", "show", f":{path}"], check=True, capture_output=True).stdout
                if staged
                else path.read_bytes()
            )
            if b"\0" in data:
                continue
            lines = data.decode("utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(lines, 1):
            has_address = any(
                match.group(1).lower() not in EXAMPLE_DOMAINS for match in EMAIL.finditer(line)
            )
            if has_address or SERVICE_NOTES.search(line):
                print(f"{path}:{number}: review public content before committing")
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    staged = "--staged" in sys.argv[1:]
    names = [name for name in sys.argv[1:] if name != "--staged"]
    sys.exit(check([Path(name) for name in names] or tracked_paths(staged), staged))

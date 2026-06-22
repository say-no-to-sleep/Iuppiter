#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "Iuppiter" / "Iuppiter"
RESOURCES = APP_ROOT / "Resources"
RESOURCE_EXTENSIONS = "jpg|jpeg|png|tif|tiff|usdz|obj|msh"
DOCUMENT_EXTENSIONS = {".md", ".txt"}
IGNORE_REFERENCED_FILENAMES = {
    "Iuppiter.png",  # default export filename, not a bundled resource
}


def swift_source() -> str:
    return "\n".join(path.read_text(errors="ignore") for path in APP_ROOT.rglob("*.swift"))


def referenced_resource_tokens(source: str) -> set[str]:
    pattern = rf'"([A-Za-z0-9_./ -]+\.({RESOURCE_EXTENSIONS}))"'
    return {
        match.group(1)
        for match in re.finditer(pattern, source, flags=re.IGNORECASE)
        if Path(match.group(1)).name not in IGNORE_REFERENCED_FILENAMES
    }


def resource_exists(token: str) -> bool:
    candidates = [
        RESOURCES / token,
        RESOURCES / "Textures" / token,
        RESOURCES / "Models" / token,
    ]
    return any(candidate.exists() for candidate in candidates)


def unreferenced_resources(source: str) -> list[Path]:
    unused: list[Path] = []
    for path in RESOURCES.rglob("*"):
        if not path.is_file() or path.suffix.lower() in DOCUMENT_EXTENSIONS:
            continue

        relative = path.relative_to(RESOURCES).as_posix()
        if relative in source or path.name in source:
            continue
        unused.append(path)
    return unused


def main() -> int:
    source = swift_source()
    references = referenced_resource_tokens(source)
    missing = sorted(token for token in references if not resource_exists(token))
    unused = sorted(unreferenced_resources(source))

    if missing:
        print("Missing referenced resources:")
        for token in missing:
            print(f"  {token}")

    if unused:
        print("Unreferenced non-doc resources:")
        for path in unused:
            print(f"  {path.relative_to(ROOT)}")

    if missing or unused:
        return 1

    print(f"Catalog resource check passed ({len(references)} referenced assets).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

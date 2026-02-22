#!/usr/bin/env python3
"""Validate local Markdown links under note directories."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


LINK_RE = re.compile(r"(?<!\!)\[[^\]]+\]\(([^)]+)\)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Markdown のローカルリンク切れを検出する")
    parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
        help="検査対象ディレクトリまたはファイル",
    )
    return parser.parse_args()


def is_external(link: str) -> bool:
    lower = link.lower()
    return (
        lower.startswith("http://")
        or lower.startswith("https://")
        or lower.startswith("mailto:")
        or lower.startswith("javascript:")
        or lower.startswith("#")
    )


def normalize_link(link: str) -> str:
    value = link.strip()
    if value.startswith("<") and value.endswith(">"):
        value = value[1:-1].strip()
    if " " in value and not value.startswith("./") and not value.startswith("../"):
        value = value.split(" ", 1)[0]
    return value


def iter_markdown_files(target: Path) -> list[Path]:
    if target.is_file():
        return [target] if target.suffix.lower() == ".md" else []

    files: list[Path] = []
    for path in target.rglob("*.md"):
        rel_parts = path.relative_to(target).parts
        if any(part.startswith(".") for part in rel_parts):
            continue
        files.append(path)
    return sorted(files)


def check_file(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        return [f"{path}:0: 読み込み失敗: {e}"]

    for lineno, line in enumerate(lines, start=1):
        for match in LINK_RE.finditer(line):
            raw_link = normalize_link(match.group(1))
            if not raw_link or is_external(raw_link):
                continue
            link_path = raw_link.split("#", 1)[0]
            if not link_path:
                continue
            resolved = (path.parent / link_path).resolve()
            if not resolved.exists():
                errors.append(f"{path}:{lineno}: リンク切れ -> {raw_link}")
    return errors


def main() -> int:
    args = parse_args()
    all_errors: list[str] = []

    for raw_target in args.paths:
        target = raw_target.resolve()
        if not target.exists():
            all_errors.append(f"{raw_target}:0: 対象が存在しません")
            continue

        for md_file in iter_markdown_files(target):
            all_errors.extend(check_file(md_file))

    if all_errors:
        print("[NG] リンク切れまたは検査エラーが見つかりました")
        for err in all_errors:
            print(err)
        return 1

    print("[OK] ローカルMarkdownリンクの検査で問題は見つかりませんでした")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

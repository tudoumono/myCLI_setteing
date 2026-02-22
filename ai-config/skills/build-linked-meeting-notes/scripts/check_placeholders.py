#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable


PLACEHOLDER_RE = re.compile(r"\{\{[^{}\n]+\}\}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Markdown ファイル内の未置換プレースホルダ（{{...}}）を検出する。"
    )
    parser.add_argument(
        "target",
        help="会議フォルダ（推奨）または Markdown ファイルのパス",
    )
    return parser.parse_args()


def iter_markdown_files(target: Path) -> Iterable[Path]:
    if target.is_file():
        if target.suffix.lower() != ".md":
            raise ValueError("Markdown ファイル（.md）を指定してください。")
        return [target]

    if not target.exists():
        raise ValueError(f"パスが存在しません: {target}")
    if not target.is_dir():
        raise ValueError(f"ディレクトリを指定してください: {target}")

    return sorted(p for p in target.rglob("*.md") if p.is_file())


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def main() -> int:
    args = parse_args()
    target = Path(args.target).expanduser().resolve()

    try:
        markdown_files = list(iter_markdown_files(target))
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        return 2

    if not markdown_files:
        print(f"[ERROR] Markdown ファイルが見つかりません: {target}")
        return 2

    findings: list[str] = []

    for md_file in markdown_files:
        text = md_file.read_text(encoding="utf-8")
        for match in PLACEHOLDER_RE.finditer(text):
            findings.append(
                f"{md_file}:{line_of(text, match.start())} 未置換プレースホルダ: {match.group(0)}"
            )

    if findings:
        print("[ERROR] 未置換プレースホルダを検出しました。")
        for item in findings:
            print(f"- {item}")
        return 1

    print(f"[OK] 未置換プレースホルダは見つかりませんでした（{len(markdown_files)} ファイル）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

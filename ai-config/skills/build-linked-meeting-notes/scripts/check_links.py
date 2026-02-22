#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable
from urllib.parse import unquote


MD_LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
FENCED_CODE_RE = re.compile(r"```.*?```", re.DOTALL)
HTML_ANCHOR_RE = re.compile(
    r"<a\s+[^>]*(?:id|name)\s*=\s*['\"]([^'\"]+)['\"][^>]*>",
    re.IGNORECASE,
)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Markdown 議事録フォルダ内のリンクとアンカーを検証する。"
    )
    parser.add_argument(
        "target",
        help="会議フォルダ（推奨）または Markdown ファイルのパス",
    )
    return parser.parse_args()


def mask_ignored_regions(text: str) -> str:
    def _mask(match: re.Match[str]) -> str:
        # 行番号を維持するため、改行以外を空白に置換する
        return re.sub(r"[^\n]", " ", match.group(0))

    masked = HTML_COMMENT_RE.sub(_mask, text)
    masked = FENCED_CODE_RE.sub(_mask, masked)
    return masked


def heading_to_anchor(heading_text: str) -> str:
    text = heading_text.strip().lower()
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"[^\w\u3040-\u30ff\u3400-\u9fff\s-]", "", text)
    text = re.sub(r"\s+", "-", text).strip("-")
    return text


def extract_anchors(markdown_path: Path) -> set[str]:
    text = markdown_path.read_text(encoding="utf-8")
    masked = mask_ignored_regions(text)
    anchors: set[str] = set()

    for match in HTML_ANCHOR_RE.finditer(masked):
        anchors.add(match.group(1))

    for match in HEADING_RE.finditer(masked):
        anchor = heading_to_anchor(match.group(2))
        if anchor:
            anchors.add(anchor)

    return anchors


def iter_markdown_files(target: Path) -> Iterable[Path]:
    if target.is_file():
        if target.suffix.lower() != ".md":
            raise ValueError("Markdown ファイル（.md）を指定してください。")
        return [target]

    if not target.exists():
        raise ValueError(f"パスが存在しません: {target}")
    if not target.is_dir():
        raise ValueError(f"ディレクトリを指定してください: {target}")

    files = sorted(p for p in target.rglob("*.md") if p.is_file())
    return files


def normalize_link_target(raw_target: str) -> str:
    target = raw_target.strip()
    if not target:
        return target

    # Markdown の title 指定 (path "title") を簡易的に除去
    if " " in target and not target.startswith("<"):
        target = target.split(" ", 1)[0]

    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]

    return unquote(target)


def is_external_link(target: str) -> bool:
    return bool(SCHEME_RE.match(target))


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

    anchor_cache: dict[Path, set[str]] = {}
    errors: list[str] = []
    warnings: list[str] = []

    def get_anchors(path: Path) -> set[str]:
        if path not in anchor_cache:
            anchor_cache[path] = extract_anchors(path)
        return anchor_cache[path]

    for md_file in markdown_files:
        text = md_file.read_text(encoding="utf-8")
        masked = mask_ignored_regions(text)

        for match in MD_LINK_RE.finditer(masked):
            raw_target = match.group(1)
            link_target = normalize_link_target(raw_target)
            if not link_target:
                continue
            if is_external_link(link_target):
                continue

            if link_target.startswith("/"):
                warnings.append(
                    f"{md_file}:{line_of(text, match.start())} 絶対パスのリンクを検出: {link_target}"
                )
                continue

            if "#" in link_target:
                path_part, fragment = link_target.split("#", 1)
            else:
                path_part, fragment = link_target, ""

            target_file = md_file if path_part == "" else (md_file.parent / path_part).resolve()

            if not target_file.exists():
                errors.append(
                    f"{md_file}:{line_of(text, match.start())} リンク先ファイルが存在しません: {link_target}"
                )
                continue

            if target_file.is_dir():
                errors.append(
                    f"{md_file}:{line_of(text, match.start())} リンク先がディレクトリです: {link_target}"
                )
                continue

            if fragment and target_file.suffix.lower() == ".md":
                anchors = get_anchors(target_file)
                if fragment not in anchors:
                    errors.append(
                        f"{md_file}:{line_of(text, match.start())} アンカーが見つかりません: {link_target}"
                    )

    if errors:
        print("[ERROR] リンク検証で問題を検出しました。")
        for err in errors:
            print(f"- {err}")
        if warnings:
            print("[WARN] 追加の注意点")
            for warn in warnings:
                print(f"- {warn}")
        return 1

    print(f"[OK] リンク検証に成功しました（{len(markdown_files)} ファイル）")
    if warnings:
        print("[WARN] 追加の注意点")
        for warn in warnings:
            print(f"- {warn}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

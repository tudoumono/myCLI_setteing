#!/usr/bin/env python3
"""Generate or update an auto-managed README index block for notes."""

from __future__ import annotations

import argparse
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path


MODE_DIRS = {
    "general": "一般資料",
    "project": "PJ特化ノート",
}

START_MARKER = "<!-- AUTO-INDEX:START -->"
END_MARKER = "<!-- AUTO-INDEX:END -->"


def jst_now_text() -> str:
    jst = timezone(timedelta(hours=9))
    return datetime.now(jst).strftime("%Y-%m-%d %H:%M")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="README の自動索引ブロック（AUTO-INDEX）を生成/更新する"
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="ノート管理ルート（例: /root/mywork/note）",
    )
    parser.add_argument(
        "--mode",
        choices=sorted(MODE_DIRS.keys()),
        help="general=一般資料, project=PJ特化ノート（--readme 未指定時に使用）",
    )
    parser.add_argument("--readme", type=Path, help="更新対象 README.md のパス")
    parser.add_argument(
        "--base-dir",
        type=Path,
        help="索引対象ディレクトリ（省略時は README と同じディレクトリ）",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="README を更新せず、生成ブロックを出力する",
    )
    return parser.parse_args()


def derive_paths(args: argparse.Namespace) -> tuple[Path, Path]:
    if args.readme:
        readme = args.readme.resolve()
        base_dir = args.base_dir.resolve() if args.base_dir else readme.parent
        return readme, base_dir

    if not args.mode:
        raise SystemExit("[ERROR] --readme を使わない場合は --mode が必要です。")

    root = args.root.resolve()
    base_dir = root / MODE_DIRS[args.mode]
    readme = base_dir / "README.md"
    if args.base_dir:
        base_dir = args.base_dir.resolve()
    return readme, base_dir


def is_hidden_path(path: Path) -> bool:
    return any(part.startswith(".") for part in path.parts)


def iter_markdown_files(base_dir: Path, readme: Path) -> list[Path]:
    files: list[Path] = []
    for path in base_dir.rglob("*.md"):
        if path.resolve() == readme.resolve():
            continue
        rel = path.relative_to(base_dir)
        if is_hidden_path(rel):
            continue
        files.append(path)
    return files


def sort_key(path: Path) -> tuple[int, int, str]:
    if path.name == "README.md":
        return (0, -1, path.name)
    match = re.match(r"^(\d+)_", path.name)
    num = int(match.group(1)) if match else 10**9
    return (1, num, path.name)


def extract_title(path: Path) -> str:
    try:
        with path.open("r", encoding="utf-8") as f:
            for _ in range(30):
                line = f.readline()
                if not line:
                    break
                match = re.match(r"^#\s+(.+?)\s*$", line)
                if match:
                    return match.group(1)
    except OSError:
        pass
    return path.stem


def group_files(files: list[Path], base_dir: Path) -> dict[str, list[Path]]:
    grouped: dict[str, list[Path]] = {}
    for path in files:
        parent_rel = path.parent.relative_to(base_dir)
        key = "." if str(parent_rel) == "." else parent_rel.as_posix()
        grouped.setdefault(key, []).append(path)
    for key in grouped:
        grouped[key].sort(key=sort_key)
    return dict(sorted(grouped.items(), key=lambda item: (item[0] != ".", item[0])))


def make_relative_link(path: Path, readme_dir: Path) -> str:
    return Path(os.path.relpath(path, start=readme_dir)).as_posix()


def render_block(grouped: dict[str, list[Path]], readme_dir: Path) -> str:
    lines: list[str] = [
        START_MARKER,
        "## 自動生成索引（管理ブロック）",
        "",
        "> このブロックは `skills/research-note-authoring/scripts/update_readme_index.py` で更新",
        f"> 更新時刻: {jst_now_text()} (JST)",
        "",
    ]

    if not grouped:
        lines.extend(["- （対象ファイルなし）", "", END_MARKER])
        return "\n".join(lines) + "\n"

    for group_name, paths in grouped.items():
        heading = "直下" if group_name == "." else group_name
        lines.append(f"### {heading}")
        for path in paths:
            title = extract_title(path)
            rel_link = make_relative_link(path, readme_dir)
            lines.append(f"- [{title}]({rel_link})")
        lines.append("")

    lines.append(END_MARKER)
    return "\n".join(lines) + "\n"


def replace_or_append_block(readme_text: str, block: str) -> str:
    pattern = re.compile(
        re.escape(START_MARKER) + r".*?" + re.escape(END_MARKER) + r"\n?",
        re.DOTALL,
    )
    if pattern.search(readme_text):
        return pattern.sub(block, readme_text, count=1)

    suffix = "" if readme_text.endswith("\n") else "\n"
    return readme_text + suffix + "\n" + block


def main() -> int:
    args = parse_args()
    readme, base_dir = derive_paths(args)

    if not readme.exists():
        raise SystemExit(f"[ERROR] README が見つかりません: {readme}")
    if not base_dir.exists():
        raise SystemExit(f"[ERROR] 索引対象ディレクトリが見つかりません: {base_dir}")

    files = iter_markdown_files(base_dir, readme)
    grouped = group_files(files, base_dir)
    block = render_block(grouped, readme.parent)

    if args.dry_run:
        print(block)
        return 0

    original = readme.read_text(encoding="utf-8")
    updated = replace_or_append_block(original, block)
    readme.write_text(updated, encoding="utf-8")
    print(f"[OK] README を更新しました: {readme}")
    print(f"[INFO] 対象ディレクトリ: {base_dir}")
    print(f"[INFO] 索引件数: {sum(len(v) for v in grouped.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

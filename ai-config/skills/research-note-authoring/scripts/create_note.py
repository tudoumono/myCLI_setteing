#!/usr/bin/env python3
"""Create a numbered note file for 一般資料 / PJ特化ノート."""

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

TEMPLATE_FILES = {
    "general": "general-note.md",
    "project": "project-note.md",
}

CATEGORY_RANGES = {
    "general": {
        "dify": (1, 9),
        "foundation": (1, 9),
        "rag": (10, 19),
        "chunking": (10, 19),
        "kb": (20, 29),
        "operations": (20, 29),
        "support": (90, 99),
        "index": (90, 99),
    },
    "project": {
        "input": (1, 9),
        "ocr": (1, 9),
        "source": (1, 9),
        "memo": (10, 19),
        "design": (10, 19),
        "implementation": (20, 29),
        "validation": (20, 29),
    },
}


def jst_now_text() -> str:
    jst = timezone(timedelta(hours=9))
    return datetime.now(jst).strftime("%Y-%m-%d %H:%M")


def sanitize_title_for_filename(title: str) -> str:
    value = title.strip()
    value = re.sub(r"[\\/:*?\"<>|]", "_", value)
    value = re.sub(r"\s+", "_", value)
    value = re.sub(r"_+", "_", value)
    return value.strip("_") or "untitled"


def collect_existing_numbers(directory: Path) -> set[int]:
    numbers: set[int] = set()
    for path in directory.glob("*.md"):
        match = re.match(r"^(\d{2})_.*\.md$", path.name)
        if match:
            numbers.add(int(match.group(1)))
    return numbers


def get_next_number(directory: Path, number_range: tuple[int, int] | None = None) -> int:
    existing = collect_existing_numbers(directory)
    if number_range is None:
        next_num = (max(existing) + 1) if existing else 1
        if not (1 <= next_num <= 99):
            raise SystemExit(
                "[ERROR] 採番が 99 を超えます。--range または --category を指定して番号帯を明示してください。"
            )
        return next_num

    start, end = number_range
    for num in range(start, end + 1):
        if num not in existing:
            return num
    raise SystemExit(
        f"[ERROR] 指定した番号帯 {start:02d}-{end:02d} は空きがありません。"
    )


def load_template(skill_root: Path, mode: str) -> str:
    template_path = skill_root / "assets" / "templates" / TEMPLATE_FILES[mode]
    return template_path.read_text(encoding="utf-8")


def render_template(template: str, title: str, root_readme_rel: str) -> str:
    content = template
    content = content.replace("{{TITLE}}", title)
    content = content.replace("{{ROOT_README_REL}}", root_readme_rel)
    content = content.replace("{{DATE_JST}}", jst_now_text())
    return content


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="採番付きノートを作成する（一般資料 / PJ特化ノート）"
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
        required=True,
        help="general=一般資料, project=PJ特化ノート",
    )
    parser.add_argument("--title", help="ノートタイトル（H1 とファイル名に使用）")
    parser.add_argument(
        "--subdir",
        help="モード配下のサブフォルダ（例: ユースケース分類）",
    )
    parser.add_argument(
        "--range",
        dest="number_range",
        help="採番する番号帯（例: 10-19）。範囲内の空き番号を使う",
    )
    parser.add_argument(
        "--category",
        help="カテゴリ別の番号帯を使う（例: generalでは rag, projectでは memo）",
    )
    parser.add_argument(
        "--list-categories",
        action="store_true",
        help="指定モードで使えるカテゴリ一覧を表示して終了（--mode 必須）",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="ファイルを書き込まず、作成予定内容を表示する",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="同名ファイルが存在する場合に上書きする",
    )
    return parser.parse_args()


def ensure_within(child: Path, parent: Path, label: str) -> None:
    try:
        child.relative_to(parent)
    except ValueError as exc:
        raise SystemExit(
            f"[ERROR] {label} が許可された範囲外です: {child}\n"
            f"許可範囲: {parent}"
        ) from exc


def parse_number_range(raw: str) -> tuple[int, int]:
    match = re.fullmatch(r"\s*(\d{1,2})\s*-\s*(\d{1,2})\s*", raw)
    if not match:
        raise SystemExit(
            f"[ERROR] --range の形式が不正です: {raw}\n"
            "例: --range 10-19"
        )
    start = int(match.group(1))
    end = int(match.group(2))
    if not (1 <= start <= 99 and 1 <= end <= 99):
        raise SystemExit("[ERROR] --range は 1-99 の範囲で指定してください。")
    if start > end:
        raise SystemExit("[ERROR] --range は開始 <= 終了で指定してください。")
    return start, end


def resolve_number_range(mode: str, raw_range: str | None, category: str | None) -> tuple[int, int] | None:
    if raw_range and category:
        raise SystemExit("[ERROR] --range と --category は同時に指定できません。")
    if raw_range:
        return parse_number_range(raw_range)
    if category:
        normalized = category.strip().lower()
        mapping = CATEGORY_RANGES.get(mode, {})
        if normalized not in mapping:
            choices = ", ".join(sorted(mapping)) or "(なし)"
            raise SystemExit(
                f"[ERROR] mode={mode} では category={category!r} は使えません。\n"
                f"使用可能: {choices}"
            )
        return mapping[normalized]
    return None


def print_categories(mode: str) -> None:
    mapping = CATEGORY_RANGES.get(mode, {})
    print(f"[INFO] mode={mode} で使用可能なカテゴリ:")
    for name in sorted(mapping):
        start, end = mapping[name]
        print(f"- {name}: {start:02d}-{end:02d}")


def main() -> int:
    args = parse_args()
    if args.list_categories:
        if not args.mode:
            raise SystemExit("[ERROR] --list-categories を使う場合は --mode が必要です。")
        print_categories(args.mode)
        return 0
    if not args.title:
        raise SystemExit("[ERROR] 新規ノート作成時は --title が必要です。")

    root = args.root.resolve()
    if not root.exists() or not root.is_dir():
        raise SystemExit(f"[ERROR] --root が存在しないディレクトリです: {root}")

    mode_root = root / MODE_DIRS[args.mode]
    if not mode_root.exists() or not mode_root.is_dir():
        raise SystemExit(
            f"[ERROR] モード対象ディレクトリが見つかりません: {mode_root}\n"
            f"--root の指定を確認してください。"
        )

    root_readme = mode_root / "README.md"
    if not root_readme.exists():
        raise SystemExit(
            f"[ERROR] ルートREADMEが見つかりません: {root_readme}\n"
            "誤った --root を指定している可能性があります。"
        )

    if args.subdir:
        subdir_path = Path(args.subdir)
        if subdir_path.is_absolute():
            raise SystemExit("[ERROR] --subdir に絶対パスは指定できません。")
        target_dir = (mode_root / subdir_path).resolve()
        ensure_within(target_dir, mode_root.resolve(), "--subdir")
    else:
        target_dir = mode_root.resolve()

    if target_dir.exists() and not target_dir.is_dir():
        raise SystemExit(f"[ERROR] 作成先がディレクトリではありません: {target_dir}")
    target_dir.mkdir(parents=True, exist_ok=True)

    selected_range = resolve_number_range(args.mode, args.number_range, args.category)
    next_num = get_next_number(target_dir, selected_range)
    safe_title = sanitize_title_for_filename(args.title)
    filename = f"{next_num:02d}_{safe_title}.md"
    target_file = target_dir / filename

    if target_file.exists() and not args.overwrite:
        raise SystemExit(
            f"[ERROR] 既に存在します: {target_file}\n"
            "必要なら --overwrite を付けてください。"
        )

    skill_root = Path(__file__).resolve().parents[1]
    template = load_template(skill_root, args.mode)
    root_readme_rel = Path(os.path.relpath(root_readme, start=target_dir)).as_posix()

    content = render_template(template, args.title, root_readme_rel)

    if args.dry_run:
        print(f"[DRY-RUN] 作成先: {target_file}")
        if selected_range:
            print(f"[DRY-RUN] 番号帯: {selected_range[0]:02d}-{selected_range[1]:02d}")
        if args.category:
            print(f"[DRY-RUN] category: {args.category}")
        print()
        print(content)
        return 0

    target_file.write_text(content, encoding="utf-8")
    print(f"[OK] 作成しました: {target_file}")
    print(f"[INFO] mode={args.mode} next_number={next_num:02d}")
    if selected_range:
        print(f"[INFO] number_range={selected_range[0]:02d}-{selected_range[1]:02d}")
    if args.category:
        print(f"[INFO] category={args.category}")
    print(
        "[NEXT] README索引を更新する場合は "
        f"`python3 {skill_root / 'scripts' / 'update_readme_index.py'} --root {root} --mode {args.mode}`"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

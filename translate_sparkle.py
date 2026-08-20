#!/usr/bin/env python3

import os
import re
import json
import shutil
from pathlib import Path

ROOT = Path("src")
MAP_FILE = Path("sparkle_cn_map.json")
BACKUP_DIR = Path("sparkle_cn_backup")

EXTENSIONS = {".m", ".mm", ".h"}

# 不处理这些目录
EXCLUDED_DIRS = {
    ".git",
    ".cache",
    "build",
    "modules",
    "vendor",
    "Pods",
    "ThirdParty",
    "third_party",
}

# Objective-C 字符串
STRING_RE = re.compile(
    r'@"((?:\\.|[^"\\])*)"'
)


def load_map():
    with MAP_FILE.open("r", encoding="utf-8") as f:
        return json.load(f)


def should_skip(path):
    return any(part in EXCLUDED_DIRS for part in path.parts)


def protect_format_tokens(text):
    """
    保护 %@ / %d / %ld / %f / %s / \\n 等格式。
    """
    tokens = []

    pattern = re.compile(
        r'%(?:[-+0-9.#]*)(?:@|d|i|u|f|lf|ld|lu|s|c|x|X)|\\[nrt"\\]'
    )

    def repl(match):
        key = f"__SPARKLE_TOKEN_{len(tokens)}__"
        tokens.append(match.group(0))
        return key

    return pattern.sub(repl, text), tokens


def restore_format_tokens(text, tokens):
    for i, token in enumerate(tokens):
        text = text.replace(
            f"__SPARKLE_TOKEN_{i}__",
            token
        )
    return text


def translate_string(original, mapping):
    # 精确匹配
    if original in mapping:
        return mapping[original]

    return None


def process_file(path, mapping):
    try:
        original_content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        print(f"[SKIP] 编码无法读取: {path}")
        return 0

    changed = 0

    def replace_match(match):
        nonlocal changed

        original = match.group(1)

        translated = translate_string(
            original,
            mapping
        )

        if translated is None:
            return match.group(0)

        # 保护格式化参数
        protected_original, original_tokens = protect_format_tokens(original)
        protected_translated, translated_tokens = protect_format_tokens(translated)

        # 翻译文本中的格式参数数量必须一致
        if sorted(original_tokens) != sorted(translated_tokens):
            print(
                f"[WARN] 格式参数不一致，跳过:\n"
                f"       {path}\n"
                f"       EN: {original}\n"
                f"       CN: {translated}"
            )
            return match.group(0)

        translated = restore_format_tokens(
            protected_translated,
            original_tokens
        )

        changed += 1

        return '@"' + translated + '"'

    new_content = STRING_RE.sub(
        replace_match,
        original_content
    )

    if new_content != original_content:
        # 自动备份
        relative = path.relative_to(ROOT)
        backup_path = BACKUP_DIR / relative

        backup_path.parent.mkdir(
            parents=True,
            exist_ok=True
        )

        if not backup_path.exists():
            shutil.copy2(path, backup_path)

        path.write_text(
            new_content,
            encoding="utf-8"
        )

        print(f"[OK] {path}  ({changed} 项)")

    return changed


def main():
    if not ROOT.exists():
        print("错误：找不到 src/")
        return 1

    if not MAP_FILE.exists():
        print("错误：找不到 sparkle_cn_map.json")
        return 1

    mapping = load_map()

    print("=" * 60)
    print(" Sparkle 源码批量汉化")
    print("=" * 60)
    print(f"词条数量: {len(mapping)}")
    print()

    total = 0
    files = 0

    for path in ROOT.rglob("*"):

        if not path.is_file():
            continue

        if path.suffix not in EXTENSIONS:
            continue

        if should_skip(path):
            continue

        count = process_file(
            path,
            mapping
        )

        if count:
            files += 1
            total += count

    print()
    print("=" * 60)
    print(f"完成：{files} 个文件")
    print(f"替换：{total} 个字符串")
    print(f"备份：{BACKUP_DIR}/")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3

import re
from pathlib import Path

ROOT = Path("src")

SKIP = {
    ".git", ".cache", "build",
    "modules", "vendor", "Pods",
    "ThirdParty", "third_party"
}

# 只处理真正 UI 参数
KEYS = (
    "title",
    "message",
    "subtitle",
    "placeholder",
    "label",
    "prompt",
    "header",
    "footer",
    "detailText",
    "accessibilityLabel",
    "accessibilityValue",
)

def valid(s):
    if not s or not re.search(r"[A-Za-z]", s):
        return False

    bad = (
        "http://", "https://", "www.",
        ".com", ".org", ".net", ".io",
        ".json", ".plist", ".png", ".jpg",
        ".jpeg", ".gif", ".mp4", ".mov",
        ".m4a", ".mp3"
    )

    return not any(x.lower() in s.lower() for x in bad)


def process(path):

    old = path.read_text(encoding="utf-8")
    new = old

    for key in KEYS:

        pattern = re.compile(
            rf'(\b{re.escape(key)}\s*:\s*)@"([^"]+)"'
        )

        def repl(m):

            prefix = m.group(1)
            text = m.group(2)

            if not valid(text):
                return m.group(0)

            # 已经处理
            if "SPKCNTranslate" in prefix:
                return m.group(0)

            return f'{prefix}SPKCNTranslate(@"{text}")'

        new = pattern.sub(repl, new)

    # self.title = @"xxx"
    for key in ("title", "subtitle", "placeholder"):

        pattern = re.compile(
            rf'(\b(?:self\.)?{key}\s*=\s*)@"([^"]+)"'
        )

        def repl2(m):

            prefix = m.group(1)
            text = m.group(2)

            if not valid(text):
                return m.group(0)

            return f'{prefix}SPKCNTranslate(@"{text}")'

        new = pattern.sub(repl2, new)

    if new != old:
        path.write_text(new, encoding="utf-8")
        print(path)


for p in ROOT.rglob("*"):

    if not p.is_file():
        continue

    if p.suffix not in {".m", ".mm", ".h"}:
        continue

    if any(x in SKIP for x in p.parts):
        continue

    process(p)

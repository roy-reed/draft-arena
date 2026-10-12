#!/usr/bin/env python3
"""校验仓库内对 Markdown 文档的引用都能从仓库根目录解析（文档搬到 docs/ 后防止遗留旧路径）。

规则：受版本控制的文本文件里，形如 `NAME.md`、`docs/NAME.md`、`store/NAME.md` 的引用
（NAME 为大写字母/下划线）必须对应存在的文件。文档自身首行标题（`# NAME.md — ...`）不算引用。
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = re.compile(r"(?<![\w./-])((?:[a-z_]+/)*[A-Z][A-Z0-9_]*\.md)\b")
EXTS = {".md", ".gd", ".py", ".ps1", ".yml", ".yaml", ".cfg", ".txt", ".sh"}


def main() -> int:
    files = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).split()
    bad = []
    for rel in files:
        path = ROOT / rel
        if path.suffix not in EXTS or not path.is_file():
            continue
        for no, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if no == 1 and line.startswith("# "):
                continue
            for ref in REF.findall(line):
                if not (ROOT / ref).is_file():
                    bad.append(f"{rel}:{no}: {ref}")
    for b in bad:
        print(f"broken doc reference: {b}", file=sys.stderr)
    print(f"doc refs: {len(bad)} broken")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

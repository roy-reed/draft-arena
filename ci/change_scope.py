#!/usr/bin/env python3
"""判断本次运行需要哪些 Godot 检查，输出 key=value 行供 GitHub Actions 的 $GITHUB_OUTPUT 使用。

game=true     需要跑 Godot 检查与构建：除纯文档/模板/标签目录外的任何改动
android=true  需要导出 Android 包：导出相关文件有变化，或分支前缀/标题范围是 mobile、android

PR 上用 git 比较合并提交与其第一父提交（目标分支），不调用 API，job 只需 contents: read，
因此被 release.yml 以 workflow_call 复用时也不会额外申请权限。
非 pull_request 事件（push main、定时、手动、release 复用）一律输出 true；判断出错也回退为 true（宁可多跑）。

本地试算：python3 ci/change_scope.py --files docs/GDD.md scripts/main.gd [--ref mobile/x] [--title "fix(mobile): …"]
"""
import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys

# 只动这些文件时不会影响游戏本体：export_presets.cfg 的 exclude_filter 已排除 *.md 与 docs/*，
# store/ 由 store/.gdignore 排除在 Godot 导入与发布包之外
DOC_ONLY = (
    "*.md",
    "docs/*",
    "store/*",
    "LICENSE*",
    ".github/ISSUE_TEMPLATE/*",
    ".github/pull_request_template.md",
    ".github/labels.json",
)
# 影响 APK 导出的文件
ANDROID_PATHS = (
    "export_presets.cfg",
    "project.godot",
    "icon.svg*",
    "ci/export-android.sh",
    "ci/install-godot-linux.sh",
    ".github/workflows/android.yml",
)
MOBILE_WORDS = {"mobile", "android"}
TITLE_SCOPE = re.compile(r"^[a-z]+\(([^)]*)\)")
ALL = {"game": True, "android": True}


def matches(path: str, patterns) -> bool:
    return any(fnmatch.fnmatchcase(path, p) for p in patterns)


def mobile_hint(head_ref: str, title: str) -> bool:
    prefix = head_ref.split("/", 1)[0].lower() if "/" in head_ref else ""
    scope = TITLE_SCOPE.match(title or "")
    words = {s.strip().lower() for s in scope.group(1).split(",")} if scope else set()
    return prefix in MOBILE_WORDS or bool(words & MOBILE_WORDS)


def classify(files, head_ref: str = "", title: str = "") -> dict:
    game = any(not matches(f, DOC_ONLY) for f in files)
    android = game and (any(matches(f, ANDROID_PATHS) for f in files) or mobile_hint(head_ref, title))
    return {"game": game, "android": android}


def merge_diff() -> list:
    """PR 合并提交相对目标分支的改动路径（--no-renames：重命名记为删旧增新，新旧路径都在列表里）。"""
    parents = subprocess.run(["git", "rev-list", "--parents", "-n", "1", "HEAD"],
                             check=True, capture_output=True, text=True).stdout.split()
    if len(parents) != 3:
        raise RuntimeError("HEAD 不是 PR 合并提交（checkout 需 fetch-depth: 2）")
    out = subprocess.run(["git", "diff", "--no-renames", "--name-only", "-z", "HEAD^1", "HEAD"],
                         check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return [p for p in out.split("\0") if p]


def detect():
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if event != "pull_request":
        return ALL, f"事件 {event or '未知'}：全量运行"
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as fh:
        pr = json.load(fh)["pull_request"]
    try:
        files = merge_diff()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as err:
        return ALL, f"PR #{pr['number']} 无法判断改动范围（{err}）：回退全量运行"
    if not files:
        return ALL, f"PR #{pr['number']} 没有文件差异：全量运行"
    return classify(files, pr["head"]["ref"], pr["title"]), f"PR #{pr['number']} 改动 {len(files)} 个路径"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--files", nargs="+", help="本地试算：直接给出改动路径")
    ap.add_argument("--ref", default="", help="本地试算：分支名")
    ap.add_argument("--title", default="", help="本地试算：PR 标题")
    args = ap.parse_args(argv)
    if args.files:
        scope, reason = classify(args.files, args.ref, args.title), f"本地试算 {len(args.files)} 个路径"
    else:
        scope, reason = detect()
    for key, value in scope.items():
        print(f"{key}={'true' if value else 'false'}")
    print(f"[change-scope] {reason}：game={scope['game']} android={scope['android']}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

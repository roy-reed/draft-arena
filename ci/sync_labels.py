#!/usr/bin/env python3
"""按 .github/labels.json 同步仓库标签：只新建或更新颜色/描述，从不删除、不改名。

默认只打印计划；加 --apply 才写入。由 .github/workflows/sync-labels.yml 在 main 上目录变化后运行。
本地试算：python3 ci/sync_labels.py --repo roy-reed/draft-arena
"""
import argparse
import json
import os
import re
import sys

import gh_rest

CATALOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, ".github", "labels.json")
COLOR = re.compile(r"^[0-9a-f]{6}$")


def load_catalog(path: str = CATALOG) -> list:
    with open(path, encoding="utf-8") as fh:
        items = json.load(fh)
    errors, seen = [], set()
    for i, item in enumerate(items):
        name = item.get("name", "")
        if not name or len(name) > 50:
            errors.append(f"#{i}: 名称为空或超过 50 字符")
        if name.lower() in seen:
            errors.append(f"#{i}: 名称重复 {name}")
        seen.add(name.lower())
        if not COLOR.match(item.get("color", "")):
            errors.append(f"#{i} {name}: 颜色须为 6 位小写十六进制")
        if len(item.get("description", "")) > 100:
            errors.append(f"#{i} {name}: 描述超过 100 字符")
    if errors:
        raise ValueError("labels.json 无效：" + "；".join(errors))
    return items


def plan(catalog, existing):
    """返回 [(动作, 名称, 载荷)]，动作为 create / update；目录外的已有标签不动。"""
    by_name = {item["name"].lower(): item for item in existing}
    steps = []
    for item in catalog:
        want = {"color": item["color"], "description": item.get("description", "")}
        have = by_name.get(item["name"].lower())
        if have is None:
            steps.append(("create", item["name"], {"name": item["name"], **want}))
        elif have.get("color", "").lower() != want["color"] or (have.get("description") or "") != want["description"]:
            steps.append(("update", have["name"], want))
    return steps


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="同步仓库标签")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""), help="owner/name")
    ap.add_argument("--apply", action="store_true", help="写入（否则只打印计划）")
    args = ap.parse_args(argv)
    catalog = load_catalog()
    steps = plan(catalog, gh_rest.paginate(f"/repos/{args.repo}/labels"))
    for action, name, body in steps:
        print(f"{'已' if args.apply else '计划'}{'新建' if action == 'create' else '更新'} {name}: {body}")
        if args.apply:
            if action == "create":
                gh_rest.request("POST", f"/repos/{args.repo}/labels", body)
            else:
                gh_rest.request("PATCH", f"/repos/{args.repo}/labels/{gh_rest.quote(name)}", body)
    print(f"labels: {len(catalog)} 个目录项，{len(steps)} 项变更{'已写入' if args.apply else '（只读试算）'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

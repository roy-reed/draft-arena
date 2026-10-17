#!/usr/bin/env python3
"""PR 卫生检查：标题格式、规模标签、高风险路径与待决策标记。

由 .github/workflows/pr-hygiene.yml 在 pull_request 事件运行；只给 PR 加/换标签，不改代码、不评论、不合并。
- 标题须符合 Conventional Commits（squash 合并时就是提交标题），不符合时本检查失败。
- size:S/M/L/XL 按增删行数保留唯一一个。
- 改动 CI、协作规则或发布配置时加 risk:L2（只加不撤，Roy 看过后手动移除）。
- 「## 待 Roy 决策」有未勾选条目或文字时加 needs-decision；条目全部勾选后自动移除（写「无」不动标签）。
- 缺少「## 验收与验证」只警告。
来自 fork 的 PR 令牌只读，只检查不写。

本地试算（只读，不写任何东西）：python3 ci/pr_hygiene.py --repo roy-reed/draft-arena --pr 21
"""
import argparse
import fnmatch
import json
import os
import re
import sys

import gh_rest

TITLE = re.compile(
    r"^(?:(?:feat|fix|perf|refactor|docs|test|ci|build|chore|revert|style)"
    r"(?:\([^()\r\n]+\))?!?: \S.*|Revert \".+\")$"
)
SIZES = ((100, "size:S"), (500, "size:M"), (1000, "size:L"), (None, "size:XL"))
RISK_LABEL = "risk:L2"
RISK_PATHS = (".github/workflows/*", "ci/*", "AGENTS.md", "export_presets.cfg", "requirements-tools.txt")
# 只新增检查登记（该文件没有删除行）属于常规改动；删改已有检查才算高风险
ADD_ONLY_OK = ("ci/run-tests.ps1",)
DECISION_LABEL = "needs-decision"
DECISION_HEADING = "待 Roy 决策"
VERIFY_HEADING = "验收与验证"
EMPTY = {"", "无", "暂无", "没有", "none", "n/a", "na", "-", "—"}
CHECKBOX = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\]")
BULLET = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")
HEADING = re.compile(r"^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
CATALOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, ".github", "labels.json")


def title_ok(title: str) -> bool:
    return bool(TITLE.match((title or "").strip()))


def size_label(lines: int) -> str:
    for limit, name in SIZES:
        if limit is None or lines < limit:
            return name
    raise AssertionError("unreachable")


def section(body: str, heading: str):
    """二级标题 heading 下的正文（到下一个一/二级标题为止，HTML 注释已去掉）；没有该标题时返回 None。"""
    text = re.sub(r"<!--.*?-->", "", (body or "").replace("\r\n", "\n"), flags=re.S)
    found = None
    for line in text.split("\n"):
        m = HEADING.match(line)
        if m and len(m.group(1)) <= 2:
            if found is not None:
                break
            if len(m.group(1)) == 2 and m.group(2).startswith(heading):
                found = []
                continue
        if found is not None:
            found.append(line)
    return None if found is None else "\n".join(found).strip()


def decision_state(body: str) -> str:
    """open：有未勾选条目或文字；resolved：只有已勾选条目；none：没写或写「无」。"""
    text = section(body, DECISION_HEADING)
    if not text:
        return "none"
    boxes = [m.group(1) != " " for m in map(CHECKBOX.match, text.split("\n")) if m]
    if boxes:
        return "resolved" if all(boxes) else "open"
    words = [BULLET.sub("", line).strip().rstrip("。.").lower() for line in text.split("\n")]
    return "open" if any(w not in EMPTY for w in words) else "none"


def risky_paths(items) -> list:
    """命中高风险路径的文件（items 为 PR 文件条目；重命名时新旧路径都检查）。"""
    hits = set()
    for item in items:
        for path in filter(None, (item.get("filename"), item.get("previous_filename"))):
            if not any(fnmatch.fnmatchcase(path, pat) for pat in RISK_PATHS):
                continue
            if path in ADD_ONLY_OK and item.get("status") == "modified" and item.get("deletions", 0) == 0:
                continue
            hits.add(path)
    return sorted(hits)


def plan_labels(current, size: str, risky: bool, decision: str):
    """返回 (要加的标签, 要去掉的标签)，都按名称排序。"""
    current = set(current)
    add = {size}
    remove = {name for name in current if name.startswith("size:") and name != size}
    if risky:
        add.add(RISK_LABEL)
    if decision == "open":
        add.add(DECISION_LABEL)
    elif decision == "resolved":
        remove.add(DECISION_LABEL)
    return sorted(add - current), sorted(remove & current)


def load_catalog() -> dict:
    with open(CATALOG, encoding="utf-8") as fh:
        return {item["name"]: item for item in json.load(fh)}


def ensure_labels(repo: str, names) -> list:
    """确保要加的标签已存在（按 .github/labels.json 的颜色与描述新建），返回新建的名称。"""
    existing = {item["name"].lower() for item in gh_rest.paginate(f"/repos/{repo}/labels")}
    catalog = load_catalog()
    created = []
    for name in names:
        if name.lower() in existing or name not in catalog:
            continue
        item = catalog[name]
        try:
            gh_rest.request("POST", f"/repos/{repo}/labels",
                            {"name": name, "color": item["color"], "description": item.get("description", "")})
            created.append(name)
        except gh_rest.GitHubError as err:
            if err.status != 422:  # 422：别的 PR 的检查刚好先建了同名标签
                raise
    return created


def apply_labels(repo: str, number: int, add, remove):
    if add:
        gh_rest.request("POST", f"/repos/{repo}/issues/{number}/labels", {"labels": list(add)})
    for name in remove:
        try:
            gh_rest.request("DELETE", f"/repos/{repo}/issues/{number}/labels/{gh_rest.quote(name)}")
        except gh_rest.GitHubError as err:
            if err.status != 404:
                raise


def load_pr(args):
    if args.pr:
        pr, _ = gh_rest.request("GET", f"/repos/{args.repo}/pulls/{args.pr}")
        return args.repo, pr
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as fh:
        return os.environ["GITHUB_REPOSITORY"], json.load(fh)["pull_request"]


def summary(rows):
    lines = ["### PR 卫生检查", "", "| 项目 | 结果 |", "|---|---|"]
    lines += [f"| {k} | {v} |" for k, v in rows]
    text = "\n".join(lines) + "\n"
    print(text)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(text)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="PR 卫生检查")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""), help="owner/name")
    ap.add_argument("--pr", type=int, help="本地试算：PR 编号（隐含 --dry-run）")
    ap.add_argument("--dry-run", action="store_true", help="只打印计划，不写标签")
    args = ap.parse_args(argv)

    repo, pr = load_pr(args)
    number = pr["number"]
    items = gh_rest.pr_files(repo, number)
    lines = sum(i.get("additions", 0) + i.get("deletions", 0) for i in items)
    risky = risky_paths(items)
    decision = decision_state(pr.get("body") or "")
    size = size_label(lines)
    current = [label["name"] for label in pr.get("labels", [])]
    add, remove = plan_labels(current, size, bool(risky), decision)

    fork = (pr.get("head", {}).get("repo") or {}).get("full_name") != repo
    dry = args.dry_run or bool(args.pr) or fork
    ok = title_ok(pr.get("title", ""))
    has_verify = section(pr.get("body") or "", VERIFY_HEADING) is not None

    if not ok:
        print(f"::error::PR 标题不符合 Conventional Commits：{pr.get('title', '')!r}；"
              "示例 fix: 修复首领越界、feat(mobile): 新增暂停按钮")
    if not has_verify:
        print("::warning::PR 描述缺少「## 验收与验证」，请按 .github/pull_request_template.md 补充")

    created = []
    if not dry and (add or remove):
        created = ensure_labels(repo, add)
        apply_labels(repo, number, add, remove)

    change = " ".join([f"+{n}" for n in add] + [f"−{n}" for n in remove]) or "无"
    if dry:
        change += "（只读试算，未写入）" if not fork else "（fork PR，只检查不写）"
    if created:
        change += f"；新建标签 {', '.join(created)}"
    decision_text = {"open": f"有未决事项 → {DECISION_LABEL}", "resolved": "已全部勾选",
                     "none": "无"}[decision]
    summary([
        ("标题", "✅ 符合" if ok else "❌ 不符合 Conventional Commits"),
        ("规模", f"{size}（{lines} 行，{len(items)} 个文件）"),
        ("高风险路径", f"{RISK_LABEL}：{', '.join(risky[:5])}{' 等' if len(risky) > 5 else ''}" if risky else "无"),
        ("待 Roy 决策", decision_text),
        ("验收与验证", "已填写" if has_verify else "⚠️ 缺少"),
        ("标签变更", change),
    ])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

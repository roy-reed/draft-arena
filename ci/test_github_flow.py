"""协作脚本的单元测试（纯标准库、不联网）：python3 -m unittest discover -s ci -p 'test_*.py'"""
import json
import configparser
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import change_scope  # noqa: E402
import pr_hygiene  # noqa: E402
import sync_labels  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class TitleTest(unittest.TestCase):
    def test_accepts_repo_style_titles(self):
        for title in (
            "fix: 处理 Windows 试玩反馈：存档退出、首领越界、散弹与属性展示",
            "feat: 去轮廓高亮、全屏呼出摇杆、召唤师陨石",
            "fix(mobile): 降低虚拟摇杆跟手延迟",
            "perf(mobile): M3 空间网格碰撞与粒子对象池，行为不变（依赖 #17）",
            "ci: PR 快速模式 / main 完整 soak",
            "feat(ui,mobile)!: 重排暂停菜单",
            'Revert "feat: 去轮廓高亮、全屏呼出摇杆、召唤师陨石"',
        ):
            self.assertTrue(pr_hygiene.title_ok(title), title)

    def test_rejects_free_form_titles(self):
        for title in ("测试：统一测试入口", "Boss 框架闭环与刷怪密度曲线", "feat:缺空格",
                      "feature: 类型不在表内", "fix(): 空范围", "Fix: 类型须小写", "feat: ", ""):
            self.assertFalse(pr_hygiene.title_ok(title), title)


class SizeTest(unittest.TestCase):
    def test_boundaries(self):
        cases = {0: "size:S", 99: "size:S", 100: "size:M", 499: "size:M",
                 500: "size:L", 999: "size:L", 1000: "size:XL", 5000: "size:XL"}
        for lines, label in cases.items():
            self.assertEqual(pr_hygiene.size_label(lines), label, lines)


TEMPLATE = open(os.path.join(ROOT, ".github", "pull_request_template.md"), encoding="utf-8").read()


class DecisionTest(unittest.TestCase):
    def test_template_default_is_none(self):
        self.assertEqual(pr_hygiene.decision_state(TEMPLATE), "none")
        self.assertIsNotNone(pr_hygiene.section(TEMPLATE, "验收与验证"))

    def test_open_resolved_and_free_text(self):
        body = "## 改动\nx\n\n## 待 Roy 决策\n- [ ] 同意：陨石伤害 30→40（备选 35）\n  建议 40\n- [x] 同意：保留旧存档\n"
        self.assertEqual(pr_hygiene.decision_state(body), "open")
        self.assertEqual(pr_hygiene.decision_state(body.replace("- [ ]", "- [x]")), "resolved")
        self.assertEqual(pr_hygiene.decision_state("## 待 Roy 决策\n散弹是否保留穿透？\n"), "open")

    def test_none_variants_and_section_boundary(self):
        for text in ("无", "- 无", "None", "暂无。", "<!-- 说明 -->\n无"):
            self.assertEqual(pr_hygiene.decision_state(f"## 待 Roy 决策\n{text}\n"), "none", text)
        body = "## 待 Roy 决策\n无\n\n## 审查重点\n- [ ] 这不是决策项\n"
        self.assertEqual(pr_hygiene.decision_state(body), "none")
        self.assertEqual(pr_hygiene.decision_state("## 改动\n- [ ] 待办\n"), "none")


class RiskAndLabelTest(unittest.TestCase):
    def item(self, name, deletions=0, status="modified", previous=None):
        return {"filename": name, "deletions": deletions, "status": status, "previous_filename": previous}

    def test_risky_paths(self):
        items = [self.item(".github/workflows/tests-linux.yml"), self.item("AGENTS.md"),
                 self.item("scripts/main.gd"), self.item("docs/GDD.md")]
        self.assertEqual(pr_hygiene.risky_paths(items), [".github/workflows/tests-linux.yml", "AGENTS.md"])

    def test_registering_a_test_is_routine(self):
        row = "    [pscustomobject]@{ Name = 'new-test'; Args = $base + @('--script', 'res://scripts/tests/new_test.gd'); Marker = 'NEW_OK' }"
        entry = dict(self.item("ci/run-tests.ps1"), additions=1, patch="@@ -40,0 +41 @@\n+" + row)
        self.assertEqual(pr_hygiene.risky_paths([entry]), [])
        for name in (".github/workflows/tests-linux.yml", "AGENTS.md", "export_presets.cfg", "ci/check_doc_refs.py"):
            self.assertIn(name, pr_hygiene.risky_paths([entry, self.item(name)]))
        for unsafe in ("Write-Output bad", row + "; exit 0", row.replace("NEW_OK", "$env:SECRET_OK")):
            self.assertEqual(pr_hygiene.risky_paths([dict(entry, patch="@@ -40,0 +41 @@\n+" + unsafe)]), ["ci/run-tests.ps1"])
        self.assertEqual(pr_hygiene.risky_paths([self.item("ci/run-tests.ps1")]), ["ci/run-tests.ps1"])
        self.assertEqual(pr_hygiene.risky_paths([dict(entry, additions=2)]), ["ci/run-tests.ps1"])
        self.assertEqual(pr_hygiene.risky_paths([dict(entry, patch=None)]), ["ci/run-tests.ps1"])
        self.assertEqual(pr_hygiene.risky_paths([self.item("ci/run-tests.ps1", deletions=2)]), ["ci/run-tests.ps1"])

    def test_rename_out_of_ci_still_counts(self):
        items = [self.item("tools/check.py", status="renamed", previous="ci/check_doc_refs.py")]
        self.assertEqual(pr_hygiene.risky_paths(items), ["ci/check_doc_refs.py"])

    def test_plan_labels(self):
        add, remove = pr_hygiene.plan_labels(["size:S", "bug"], "size:M", True, "open")
        self.assertEqual(add, ["needs-decision", "risk:L2", "size:M"])
        self.assertEqual(remove, ["size:S"])
        add, remove = pr_hygiene.plan_labels(["size:M", "needs-decision", "risk:L2"], "size:M", False, "resolved")
        self.assertEqual((add, remove), ([], ["needs-decision"]))
        add, remove = pr_hygiene.plan_labels(["needs-decision"], "size:S", False, "none")
        self.assertEqual((add, remove), (["size:S"], []))


class ChangeScopeTest(unittest.TestCase):
    def test_docs_only_skips_godot(self):
        files = ["docs/GDD.md", "README.md", ".github/pull_request_template.md", ".github/labels.json",
                 ".github/ISSUE_TEMPLATE/bug_report.yml", "store/STORE_COPY.md"]
        self.assertEqual(change_scope.classify(files, "mobile/x", "docs(mobile): 文案"),
                         {"game": False, "android": False})

    def test_code_and_android(self):
        self.assertEqual(change_scope.classify(["scripts/main.gd"]), {"game": True, "android": False})
        self.assertEqual(change_scope.classify(["export_presets.cfg"]), {"game": True, "android": True})
        self.assertEqual(change_scope.classify(["scripts/ui.gd"], "mobile/m4-x"), {"game": True, "android": True})
        self.assertEqual(change_scope.classify(["scripts/ui.gd"], "fix/x", "fix(ui,android): 返回键"),
                         {"game": True, "android": True})
        self.assertEqual(change_scope.classify([".github/workflows/pr-hygiene.yml"]), {"game": True, "android": False})


class WorkflowEventsTest(unittest.TestCase):
    def test_metadata_and_draft_consumers(self):
        def workflow(name):
            return (Path(ROOT) / ".github/workflows" / (name + ".yml")).read_text()
        for name in ("android", "pr-hygiene"):
            self.assertRegex(workflow(name), r"types: \[[^\]]*edited")
        for name in ("android", "build-windows"):
            for event in ("ready_for_review", "converted_to_draft"):
                self.assertRegex(workflow(name), r"types: \[[^\]]*" + event)
        for name in ("tests-linux", "sync-labels", "build-windows"):
            self.assertNotIn("edited", workflow(name))


class MergeScopeTest(unittest.TestCase):
    def test_real_merge_commits_and_fallback(self):
        cases = (
            ("docs", {"docs/note.md": "text"}, None, False, False),
            ("code", {"scripts/example.gd": "code"}, None, True, False),
            ("export-rename", {}, ("export_presets.cfg", "old.cfg"), True, True),
            ("ignored-store", {"store/new.png": "asset"}, None, False, False),
            ("missing-ignore", {"store/new.png": "asset", "store/.gdignore": None}, None, True, False),
            ("ignore-only", {"store/.gdignore": None}, None, True, False),
            ("store-md", {"store/note.md": "text", "store/.gdignore": None}, None, True, False),
        )
        for name, changes, rename, game, android in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                def git(*args):
                    return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.DEVNULL, text=True).strip()
                def write(rel, content):
                    path = root / rel
                    path.parent.mkdir(parents=True, exist_ok=True)
                    if content is None:
                        path.unlink()
                    else:
                        path.write_text(content)
                git("init", "-b", "base")
                git("config", "user.name", "Scope Test")
                git("config", "user.email", "scope@example.invalid")
                for rel in ("export_presets.cfg", "store/.gdignore", "README.md"):
                    write(rel, "base")
                git("add", ".")
                git("commit", "-qm", "base")
                git("checkout", "-qb", "topic")
                for rel, content in changes.items():
                    write(rel, content)
                if rename:
                    git("mv", *rename)
                git("add", "-A")
                git("commit", "-qm", "topic")
                event = root / "event.json"
                event.write_text(json.dumps({"pull_request": {"number": 1, "head": {"ref": "fix/test"}, "title": "fix: test"}}))
                env = dict(os.environ, GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event))
                def detect():
                    result = subprocess.run([sys.executable, str(Path(ROOT) / "ci/change_scope.py")], cwd=root,
                                            env=env, capture_output=True, text=True, check=True)
                    return result.stdout, result.stderr
                out, err = detect()
                self.assertEqual(out, "game=true\nandroid=true\n")
                self.assertIn("回退全量", err)
                git("checkout", "base")
                git("merge", "--no-ff", "topic", "-m", "merge")
                out, _ = detect()
                self.assertEqual(out, f"game={str(game).lower()}\nandroid={str(android).lower()}\n")
                print(f"MERGE_SCOPE_OK {name}: {out.strip().replace(chr(10), ' ')}; non-merge=all")

    def test_store_without_marker_and_export_contract(self):
        with tempfile.TemporaryDirectory() as tmp, patch("os.getcwd", return_value=tmp):
            self.assertEqual(change_scope.classify(["store/unlisted.png"]), {"game": True, "android": False})
            self.assertEqual(change_scope.classify(["store/note.md"]), {"game": False, "android": False})
        cfg = configparser.ConfigParser()
        cfg.read(Path(ROOT) / "export_presets.cfg")
        for section in cfg.sections():
            if cfg.has_option(section, "exclude_filter"):
                patterns = cfg.get(section, "exclude_filter").strip('"').split(',')
                for pattern in ("*.md", "docs/*"):
                    self.assertIn(pattern, patterns)


class LabelCatalogTest(unittest.TestCase):
    def test_catalog_valid_and_complete(self):
        names = {item["name"] for item in sync_labels.load_catalog()}
        needed = {"size:S", "size:M", "size:L", "size:XL", pr_hygiene.RISK_LABEL, pr_hygiene.DECISION_LABEL}
        forms = os.path.join(ROOT, ".github", "ISSUE_TEMPLATE")
        for name in os.listdir(forms):
            text = open(os.path.join(forms, name), encoding="utf-8").read()
            for match in re.finditer(r"^labels:\s*\[(.*)\]\s*$", text, flags=re.M):
                needed |= set(json.loads(f"[{match.group(1)}]"))
        self.assertTrue(needed <= names, needed - names)

    def test_sync_plan_never_deletes(self):
        catalog = [{"name": "bug", "color": "d73a4a", "description": "x"},
                   {"name": "size:S", "color": "c2e0c6", "description": "小"}]
        existing = [{"name": "Bug", "color": "D73A4A", "description": "y"}, {"name": "wontfix", "color": "ffffff"}]
        self.assertEqual(sync_labels.plan(catalog, existing), [
            ("update", "Bug", {"color": "d73a4a", "description": "x"}),
            ("create", "size:S", {"name": "size:S", "color": "c2e0c6", "description": "小"}),
        ])
        self.assertEqual(sync_labels.plan(catalog[:1], [{"name": "bug", "color": "d73a4a", "description": "x"}]), [])


if __name__ == "__main__":
    unittest.main()

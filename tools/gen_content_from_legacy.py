#!/usr/bin/env python3
"""一次性迁移工具（arch-v2 M1）：从旧 scripts/cards.gd 的牌字典与 player.gd 的 upgrade_weapon 查表
生成 content/ 下的 .tres 数据。迁移完成后旧硬编码已删除，本脚本保留作记录，并演示 AI/脚本批量产出 .tres 的格式。
用法：python3 tools/gen_content_from_legacy.py <cards.gd> <player.gd>
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPS = {"ADD": 0, "SCALE": 1, "SET_TRUE": 2, "CALL": 3, "CALL_ARG": 4}
TAGS = {
    "p_whetstone": ["crit"], "p_ammo_belt": ["tempo"], "p_anvil": ["survival"], "p_sneakers": ["tempo"],
    "p_thorns": ["survival"], "p_fang": ["survival"], "p_magnet": ["greed"], "p_frost": ["control"],
    "p_double": ["bullet"], "p_crit": ["crit"], "p_berserk": ["fury"], "p_giantslayer": ["crit"],
    "p_regen": ["survival"], "p_revenge": ["fury"], "p_swift": ["tempo"], "p_lens": ["bullet"],
    "p_armor": ["survival"], "p_golden": ["greed"], "p_grit": ["fury"], "p_burst": ["blast"], "p_glass": ["fury"],
}
WTAG = {"w_dragon": "bullet", "w_sniper": "bullet", "w_shotgun": "bullet", "w_boomerang": "boomerang", "w_arc": "arc", "w_sawblade": "melee"}

def parse_effect(src):
    src = src.strip()
    if m := re.fullmatch(r"p\.(\w+) \+= ([\d.]+)", src): return [(m[1], "ADD", float(m[2]))]
    if m := re.fullmatch(r"p\.(\w+) \*= ([\d.]+)", src): return [(m[1], "SCALE", float(m[2]))]
    if m := re.fullmatch(r"p\.(\w+) = true", src): return [(m[1], "SET_TRUE", 0.0)]
    if m := re.fullmatch(r"p\.(\w+)\(\)", src): return [(m[1], "CALL", 0.0)]
    if m := re.fullmatch(r"p\.(\w+)\((-?[\d.]+)\)", src): return [(m[1], "CALL_ARG", float(m[2]))]
    raise SystemExit(f"无法解析效果：{src}")

def q(s): return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def mods_block(mods, start):
    subs, refs = [], []
    for i, (stat, op, val) in enumerate(mods, start):
        subs.append(f'[sub_resource type="Resource" id="m{i}"]\nscript = ExtResource("mod")\nstat = &"{stat}"\nop = {OPS[op]}\nvalue = {val}\n')
        refs.append(f'SubResource("m{i}")')
    return subs, refs

def write_card(c):
    mods = parse_effect(c["apply"])
    subs, refs = mods_block(mods, 0)
    lines = [f'[gd_resource type="Resource" load_steps={len(subs) + 3} format=3]', "",
             '[ext_resource type="Script" path="res://scripts/core/card_def.gd" id="card"]',
             '[ext_resource type="Script" path="res://scripts/core/stat_modifier.gd" id="mod"]', ""]
    lines += subs
    body = ["[resource]", 'script = ExtResource("card")', f'id = &"{c["id"]}"', f'kind = "{c["kind"]}"',
            f'display_name = {q(c["name"])}', f'desc = {q(c["desc"])}', f'm0 = {"true" if c.get("m0") else "false"}']
    if c["kind"] == "weapon":
        body += [f'owner_char = &"{c["owner"]}"', f'weapon = &"{c["weapon"]}"', f'tier = {c["tier"]}']
    if c.get("req"):
        body.append("req = PackedStringArray(" + ", ".join(q(r) for r in c["req"]) + ")")
    tags = TAGS.get(c["id"], [WTAG.get(c.get("weapon", ""), "")])
    body.append("tags = PackedStringArray(" + ", ".join(q(t) for t in tags if t) + ")")
    body.append(f'modifiers = Array[Resource]([{", ".join(refs)}])')
    (ROOT / "content/cards" / f'{c["id"]}.tres').write_text("\n".join(lines + body) + "\n", encoding="utf-8")

def main():
    cards_src = Path(sys.argv[1]).read_text(encoding="utf-8")
    player_src = Path(sys.argv[2]).read_text(encoding="utf-8")
    cards = []
    for line in cards_src.splitlines():
        if '"apply": func(p):' not in line: continue
        c = {k: v for k, v in re.findall(r'"(\w+)": "([^"]*)"', line)}
        c["tier"] = int(m[1]) if (m := re.search(r'"tier": (\d+)', line)) else 0
        c["m0"] = '"m0": true' in line
        c["req"] = re.findall(r'"(\w+)"', m[1]) if (m := re.search(r'"req": \[([^\]]*)\]', line)) else []
        c["apply"] = re.search(r'"apply": func\(p\): (.*)\},\s*$', line)[1]
        cards.append(c); write_card(c)
    weapons = dict(re.findall(r'"(w_\w+)": \{"name": "([^"]+)", "interval_mult": ([\d.]+)\}', cards_src) and
                   [(w, (n, float(i))) for w, n, i in re.findall(r'"(w_\w+)": \{"name": "([^"]+)", "interval_mult": ([\d.]+)\}', cards_src)])
    owners = {c["weapon"]: c["owner"] for c in cards if c["kind"] == "weapon"}
    match = player_src.split("func upgrade_weapon()")[1].split("\nfunc ")[0]
    levels = {}
    for w, lv, body in re.findall(r'\["(w_\w+)", (\d)\]:[^\n]*\n((?:\t\t\t[^\n]*\n)+)', match):
        levels.setdefault(w, {})[int(lv)] = [parse_effect("p." + l.split("#")[0].strip())[0] for l in body.strip().splitlines()]
    for w, (name, im) in weapons.items():
        ext = ['[ext_resource type="Script" path="res://scripts/core/weapon_def.gd" id="wdef"]',
               '[ext_resource type="Script" path="res://scripts/core/weapon_level.gd" id="wlv"]',
               '[ext_resource type="Script" path="res://scripts/core/stat_modifier.gd" id="mod"]']
        subs, lvrefs, n = [], [], 0
        for lv in sorted(levels[w]):
            s, refs = mods_block(levels[w][lv], n); n += len(s); subs += s
            subs.append(f'[sub_resource type="Resource" id="lv{lv}"]\nscript = ExtResource("wlv")\nlevel = {lv}\nmodifiers = Array[Resource]([{", ".join(refs)}])\n')
            lvrefs.append(f'SubResource("lv{lv}")')
        txt = [f'[gd_resource type="Resource" load_steps={len(subs) + 4} format=3]', ""] + ext + [""] + subs + [
            "[resource]", 'script = ExtResource("wdef")', f'id = &"{w}"', f'display_name = {q(name)}', f'interval_mult = {im}',
            f'mech_tag = &"{WTAG[w]}"', f'owner_char = &"{owners[w]}"', f'levels = Array[Resource]([{", ".join(lvrefs)}])']
        (ROOT / "content/weapons" / f"{w}.tres").write_text("\n".join(txt) + "\n", encoding="utf-8")
    order = re.search(r"UNLOCK_ORDER := \[([^\]]*)\]", cards_src)[1]
    order_ids = re.findall(r'"(\w+)"', order)
    ext, ci = ['[ext_resource type="Script" path="res://scripts/core/content_library.gd" id="lib"]',
               '[ext_resource type="Script" path="res://scripts/core/weapon_def.gd" id="wdef"]',
               '[ext_resource type="Script" path="res://scripts/core/card_def.gd" id="card"]'], []
    for w in weapons: ext.append(f'[ext_resource type="Resource" path="res://content/weapons/{w}.tres" id="{w}"]')
    for c in cards: ext.append(f'[ext_resource type="Resource" path="res://content/cards/{c["id"]}.tres" id="{c["id"]}"]')
    txt = [f'[gd_resource type="Resource" load_steps={len(ext) + 1} format=3]', ""] + ext + ["",
           "[resource]", 'script = ExtResource("lib")',
           f'weapons = Array[Resource]([{", ".join(f"ExtResource({q(w)})" for w in weapons)}])',
           f'cards = Array[Resource]([{", ".join(f"ExtResource({q(c["id"])})" for c in cards)}])',
           "unlock_order = PackedStringArray(" + ", ".join(q(i) for i in order_ids) + ")"]
    (ROOT / "content/library.tres").write_text("\n".join(txt) + "\n", encoding="utf-8")
    print(f"generated {len(cards)} cards, {len(weapons)} weapons, {sum(len(v) for v in levels.values())} weapon levels")

if __name__ == "__main__":
    main()

# -*- coding: utf-8 -*-
"""一次性修复：CI yml 中被 \4 八进制转义污染的控制字符 \x04 → 字面量 \\4.4.1.stable"""
p = ".github/workflows/build-windows.yml"
data = open(p, "rb").read()
assert b"\x04" in data, "控制字符不存在（已修？）"
data = data.replace(b"export_templates\x04.4.1.stable", b"export_templates\\4.4.1.stable")
with open(p, "wb") as f:
    f.write(data)
check = open(p, "rb").read()
assert b"\x04" not in check, "写入后仍存在"
assert b"export_templates\\4.4.1.stable" in check
print("FIXED: 控制字符已替换为字面反斜杠路径")

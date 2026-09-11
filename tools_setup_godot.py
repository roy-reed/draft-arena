# -*- coding: utf-8 -*-
"""环境引导：下载 Godot 4.4.1-stable 到仓库内 .tools/godot/（win/linux 自适应）。
用法：python tools_setup_godot.py [--force]
纯标准库；已存在时跳过。"""
import os
import platform
import stat
import sys
import urllib.request
import zipfile

VERSION = "4.4.1-stable"
BASE = "https://github.com/godotengine/godot/releases/download/" + VERSION + "/"

# 平台 -> (zip 名, {zip 内文件: 输出文件名})
PKGS = {
    ("Windows", "amd64"): (
        "Godot_v" + VERSION + "_win64.exe.zip",
        {
            "Godot_v" + VERSION + "_win64.exe": "godot.exe",
            "Godot_v" + VERSION + "_win64_console.exe": "godot_console.exe",
        },
    ),
    ("Linux", "amd64"): (
        "Godot_v" + VERSION + "_linux.x86_64.zip",
        {"Godot_v" + VERSION + "_linux.x86_64": "godot"},
    ),
}


def download(url: str, dest: str) -> None:
    """下载优先 curl（本环境已验证可用、自动走系统代理），失败回退 urllib"""
    import shutil
    import subprocess
    if shutil.which("curl"):
        r = subprocess.run(["curl", "-L", "--connect-timeout", "30", "--retry", "2", "-o", dest, url])
        if r.returncode == 0 and os.path.getsize(dest) > 1024 * 1024:
            return
        if os.path.exists(dest):
            os.remove(dest)
        print("curl 失败，回退 urllib……")
    urllib.request.urlretrieve(url, dest)


def main():
    force = "--force" in sys.argv
    machine = "amd64" if platform.machine().lower() in ("amd64", "x86_64") else platform.machine().lower()
    key = (platform.system(), machine)
    if key not in PKGS:
        print("不支持的平台:", key, "；请手动下载", BASE)
        return 1
    zip_name, rename_map = PKGS[key]
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".tools", "godot")
    marker = os.path.join(out_dir, "godot.exe" if os.name == "nt" else "godot")
    if os.path.exists(marker) and not force:
        print("已存在：", marker, "（--force 重装）")
        return 0
    os.makedirs(out_dir, exist_ok=True)
    url = BASE + zip_name
    tmp_zip = os.path.join(out_dir, zip_name)
    # 网络不通时依次尝试：GODOT_ZIP 环境变量指向的本地 zip → 工作区上级已有引擎
    alt_zip = os.environ.get("GODOT_ZIP", "")
    sibling = None
    for cand in (os.path.join("..", "..", ".tools", "godot"), os.path.join("..", ".tools", "godot")):
        c = os.path.abspath(os.path.join(out_dir, cand, "godot.exe" if os.name == "nt" else "godot"))
        if os.path.exists(c):
            sibling = os.path.dirname(c)
            break
    if not os.path.exists(url if False else tmp_zip) and not alt_zip and sibling:
        import shutil
        print("网络可能不通：从已有引擎复制", sibling)
        for f in os.listdir(sibling):
            if f.startswith("godot"):
                shutil.copy2(os.path.join(sibling, f), os.path.join(out_dir, f))
        print("完成。可执行文件：", marker, "（来源：本地已有引擎）")
        return 0
    print("下载", url)
    download(url, tmp_zip)
    extracted = []
    with zipfile.ZipFile(tmp_zip) as z:
        for info in z.infolist():
            if info.is_dir() or info.filename not in rename_map:
                continue
            target = os.path.join(out_dir, rename_map[info.filename])
            with z.open(info) as src, open(target, "wb") as dst:
                dst.write(src.read())
            if os.name != "nt":
                os.chmod(target, os.stat(target).st_mode | stat.S_IEXEC)
            extracted.append(rename_map[info.filename])
    os.remove(tmp_zip)
    if marker not in [os.path.join(out_dir, e) for e in extracted]:
        print("错误：压缩包内未找到主程序", rename_map)
        return 1
    print("完成。可执行文件：", marker)
    return 0


if __name__ == "__main__":
    sys.exit(main())

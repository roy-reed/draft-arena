#!/usr/bin/env bash
# 用法：ci/package-release.sh <tag> <DraftArena.exe 路径> <输出目录> [已签名的 Android APK 路径]
# 产物：<输出目录>/DraftArena-<tag>-windows-x86_64.zip、（可选）DraftArena-<tag>-android-arm64.apk
#       与 SHA256SUMS.txt（覆盖全部产物，sha256sum -c 可直接校验）
set -euo pipefail
tag="${1:?tag}"; exe="${2:?exe}"; out="${3:?outdir}"; apk="${4:-}"
[[ "$tag" =~ ^v[0-9A-Za-z._-]+$ ]] || { echo "invalid tag: $tag" >&2; exit 1; }
[[ -s "$exe" ]] || { echo "missing exe: $exe" >&2; exit 1; }
if [[ -n "$apk" ]]; then [[ -s "$apk" ]] || { echo "missing apk: $apk" >&2; exit 1; }; fi
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
name="DraftArena-${tag}-windows-x86_64"
mkdir "$stage/$name"
cp "$exe" "$stage/$name/DraftArena.exe"
cat > "$stage/$name/README.txt" <<TXT
Draft Arena ${tag} (Windows x86_64)

运行：解压后双击 DraftArena.exe，无需安装。
系统要求：Windows 10/11 64 位，支持 OpenGL 3.3 的显卡（游戏使用 Godot Compatibility 渲染器）。
程序未做代码签名，首次运行时 Windows SmartScreen 可能提示“已保护你的电脑”，
确认来源后点“更多信息”→“仍要运行”。
校验：SHA256SUMS.txt 与 Releases 页面一同发布。
源码与说明：https://github.com/roy-reed/draft-arena
TXT
if [[ -f "$root/LICENSE" ]]; then cp "$root/LICENSE" "$stage/$name/"; fi
python3 - "$stage" "$name" "$out/$name.zip" <<'PY'
import os, sys, zipfile
stage, name, dst = sys.argv[1:]
# 固定时间戳与顺序，使同一输入得到逐字节相同的 zip
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirs, files in os.walk(os.path.join(stage, name)):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(dirpath, f)
            info = zipfile.ZipInfo(os.path.relpath(full, stage), (2000, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(full, "rb") as fh:
                z.writestr(info, fh.read())
PY
files=("$name.zip")
if [[ -n "$apk" ]]; then
  apk_name="DraftArena-${tag}-android-arm64.apk"
  cp "$apk" "$out/$apk_name"
  files+=("$apk_name")
fi
(cd "$out" && sha256sum "${files[@]}" > SHA256SUMS.txt)
cat "$out/SHA256SUMS.txt"

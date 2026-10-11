#!/usr/bin/env bash
# 下载 Godot Linux 编辑器到 $1（默认 .tools/godot-linux），并在解压前校验官方 SHA512-SUMS.txt 中的 SHA-512。
# 需要环境变量 GODOT_VERSION、GODOT_LINUX_SHA512；可用 GODOT_LINUX_ZIP 指定已下载的本地 zip（离线复现）。
set -euo pipefail
: "${GODOT_VERSION:?}" "${GODOT_LINUX_SHA512:?}"
dest="${1:-.tools/godot-linux}"
name="Godot_v${GODOT_VERSION}_linux.x86_64"
mkdir -p "$dest"
zip="${GODOT_LINUX_ZIP:-$dest/$name.zip}"
if [[ -z "${GODOT_LINUX_ZIP:-}" ]]; then
  curl -fsSL --retry 3 -o "$zip" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${name}.zip"
fi
actual="$(sha512sum "$zip" | cut -d' ' -f1)"
if [[ "$actual" != "$GODOT_LINUX_SHA512" ]]; then
  echo "Godot Linux SHA-512 mismatch: $actual" >&2
  exit 1
fi
unzip -oq "$zip" -d "$dest"
chmod +x "$dest/$name"
ln -sf "$name" "$dest/godot"
echo "Godot ${GODOT_VERSION} verified -> $dest/godot"

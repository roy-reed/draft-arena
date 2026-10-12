#!/usr/bin/env bash
# 导出 Android arm64 APK 并校验签名与清单。
#
# 用法：ci/export-android.sh <debug|release> <输出 apk 路径> [版本标签 vX.Y.Z]
#
# 必需环境变量：
#   GODOT          Godot 4.4.1 Linux 编辑器可执行文件（ci/install-godot-linux.sh 安装）
#   ANDROID_HOME   Android SDK 根目录（需含 build-tools；GitHub ubuntu runner 已预装）
#   JAVA_HOME      JDK 17
# 可选：
#   GODOT_TEMPLATES_TPZ  已下载的官方导出模板 tpz（离线复现）；否则从官方发布下载，均先校验 SHA-512
#   ANDROID_TOOLS_DIR    模板与编辑器设置的隔离目录（默认 .tools/android-export），不写入 ~/.config
# release 模式必需（由 GitHub Secrets 传入，脚本不回显）：
#   ANDROID_RELEASE_KEYSTORE_PATH / ANDROID_RELEASE_KEY_ALIAS / ANDROID_RELEASE_KEYSTORE_PASSWORD
# debug 模式：若未提供 ANDROID_DEBUG_KEYSTORE_PATH，则用 keytool 临时生成一次性 debug keystore。
set -euo pipefail
mode="${1:?debug|release}"; out="${2:?output apk}"; tag="${3:-}"
case "$mode" in debug|release) ;; *) echo "mode must be debug or release" >&2; exit 2 ;; esac
: "${GODOT:?}" "${ANDROID_HOME:?}" "${JAVA_HOME:?}"
GODOT_VERSION="${GODOT_VERSION:-4.4.1-stable}"
# SHA-512 取自 Godot 官方 SHA512-SUMS.txt（4.4.1-stable，Godot_v4.4.1-stable_export_templates.tpz），与 build-windows.yml 相同
TEMPLATES_SHA512="8f461c7d6e91a0fbabfc95b1e4ca70ff1732c6f2920956a16b086ec2a85b5f7e238baf4dbce60dcc5630fae3bcb9a1fa2ae2027b92cb495c02d082705715e441"
PACKAGE="com.royreed.draftarena"

root="$(cd "$(dirname "$0")/.." && pwd)"
tools="$(mkdir -p "${ANDROID_TOOLS_DIR:-$root/.tools/android-export}" && cd "${ANDROID_TOOLS_DIR:-$root/.tools/android-export}" && pwd)"
tpl_dir="$tools/data/godot/export_templates/${GODOT_VERSION/-/.}"
mkdir -p "$(dirname "$out")"; out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

# 1) 导出模板：只解出 android_*，校验整包 SHA-512
if [[ ! -s "$tpl_dir/android_${mode}.apk" ]]; then
  tpz="${GODOT_TEMPLATES_TPZ:-$tools/templates.tpz}"
  if [[ -z "${GODOT_TEMPLATES_TPZ:-}" ]]; then
    curl -fsSL --retry 3 -o "$tpz" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
  fi
  actual="$(sha512sum "$tpz" | cut -d' ' -f1)"
  [[ "$actual" == "$TEMPLATES_SHA512" ]] || { echo "export templates SHA-512 mismatch: $actual" >&2; exit 1; }
  mkdir -p "$tpl_dir"
  unzip -joq "$tpz" 'templates/android_debug.apk' 'templates/android_release.apk' 'templates/version.txt' -d "$tpl_dir"
  [[ -z "${GODOT_TEMPLATES_TPZ:-}" ]] && rm -f "$tpz"
fi

# 2) 隔离的编辑器设置（XDG 指向 tools 目录，不读写用户 ~/.config/godot）
export XDG_DATA_HOME="$tools/data" XDG_CONFIG_HOME="$tools/config" XDG_CACHE_HOME="$tools/cache"
mkdir -p "$XDG_CONFIG_HOME/godot"
cat > "$XDG_CONFIG_HOME/godot/editor_settings-4.4.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
TRES

# 3) 签名：Godot 4 读取 GODOT_ANDROID_KEYSTORE_{DEBUG,RELEASE}_{PATH,USER,PASSWORD}
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
if [[ "$mode" == debug ]]; then
  if [[ -z "${ANDROID_DEBUG_KEYSTORE_PATH:-}" ]]; then
    "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$work/debug.keystore" -storepass android -keypass android \
      -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
    ANDROID_DEBUG_KEYSTORE_PATH="$work/debug.keystore"
  fi
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$ANDROID_DEBUG_KEYSTORE_PATH"
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${ANDROID_DEBUG_KEY_ALIAS:-androiddebugkey}"
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${ANDROID_DEBUG_KEYSTORE_PASSWORD:-android}"
else
  : "${ANDROID_RELEASE_KEYSTORE_PATH:?release keystore path missing (GitHub Secret)}"
  : "${ANDROID_RELEASE_KEY_ALIAS:?release key alias missing (GitHub Secret)}"
  : "${ANDROID_RELEASE_KEYSTORE_PASSWORD:?release keystore password missing (GitHub Secret)}"
  [[ -s "$ANDROID_RELEASE_KEYSTORE_PATH" ]] || { echo "release keystore file is empty" >&2; exit 1; }
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$ANDROID_RELEASE_KEYSTORE_PATH"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ANDROID_RELEASE_KEY_ALIAS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$ANDROID_RELEASE_KEYSTORE_PASSWORD"
fi

# 4) 在临时副本中导出，不改动工作树；有标签时写入 version/name 与单调递增的 version/code
proj="$work/project"; mkdir "$proj"
tar -C "$root" --exclude=./.git --exclude=./.tools --exclude=./.godot --exclude=./dist -cf - . | tar -C "$proj" -xf -
if [[ -n "$tag" ]]; then
  [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]] || { echo "tag must look like vX.Y.Z: $tag" >&2; exit 1; }
  code=$(( BASH_REMATCH[1] * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3] ))
  (( code > 0 )) || code=1
  sed -i -e "s/^version\/code=.*/version\/code=$code/" -e "s/^version\/name=.*/version\/name=\"${tag#v}\"/" "$proj/export_presets.cfg"
fi
"$GODOT" --headless --path "$proj" --import >"$work/import.log" 2>&1 || { cat "$work/import.log"; exit 1; }
rm -f "$out"
set +e
"$GODOT" --headless --path "$proj" "--export-$mode" Android "$out" >"$work/export.log" 2>&1
rc=$?
set -e
grep -vi 'password' "$work/export.log" || true
if (( rc != 0 )) || [[ ! -s "$out" ]]; then echo "Android export failed (exit $rc)" >&2; exit 1; fi
if grep -qiE '^(ERROR|SCRIPT ERROR)' "$work/export.log"; then echo "Android export logged errors" >&2; exit 1; fi

# 5) 校验：签名有效、包名、仅 arm64、横屏
bt="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)"
"$bt/apksigner" verify --print-certs "$out" > "$work/certs.txt"
badging="$("$bt/aapt2" dump badging "$out" 2>/dev/null)"
grep -q "^package: name='$PACKAGE'" <<<"$badging" || { echo "unexpected package name" >&2; exit 1; }
grep -q "^native-code: 'arm64-v8a'$" <<<"$badging" || { echo "expected arm64-v8a only" >&2; grep native-code <<<"$badging" >&2; exit 1; }
# screenOrientation 取值：0 landscape / 6 sensorLandscape / 8 reverseLandscape / 11 userLandscape
orient="$("$bt/aapt2" dump xmltree --file AndroidManifest.xml "$out" 2>/dev/null | sed -n 's/.*android:screenOrientation([^)]*)=\([0-9]*\).*/\1/p' | head -1)"
[[ "$orient" =~ ^(0|6|8|11)$ ]] || { echo "expected landscape orientation, got '${orient}'" >&2; exit 1; }
if [[ "$mode" == release ]]; then
  grep -q "CN=Android Debug" "$work/certs.txt" && { echo "release APK signed with debug key" >&2; exit 1; }
fi
sed -n 's/^Signer #1 certificate SHA-256 digest: /signer-sha256: /p' "$work/certs.txt"
grep -E "^package:|^native-code:" <<<"$badging"; echo "screenOrientation=$orient"
echo "ANDROID_EXPORT_OK $mode $(sha256sum "$out" | cut -d' ' -f1) $(stat -c%s "$out") bytes"

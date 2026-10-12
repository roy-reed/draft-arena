# Draft Arena

Brotato 式短局肉鸽竞技场 + 经验升级选卡构筑。像素风，Godot 4.4.1，目标低价买断上架 Steam（先 Next Fest）。单人开发，agent 协作推进。

## 下载游玩

只想玩游戏：到 **[Releases 最新版本](https://github.com/roy-reed/draft-arena/releases/latest)** 下载对应平台的文件。

**Windows**：下载 `DraftArena-<版本>-windows-x86_64.zip`，解压后双击 `DraftArena.exe` 即可运行，无需安装。

- 系统要求：Windows 10/11 64 位；显卡支持 OpenGL 3.3（游戏使用 Godot Compatibility 渲染器）。
- 未签名提示：程序没有代码签名，首次运行时 Windows SmartScreen 可能提示“Windows 已保护你的电脑”。确认文件来自本仓库 Releases 后，点“更多信息”→“仍要运行”。
- 校验（可选）：同页的 `SHA256SUMS.txt` 记录了 zip 的 SHA-256。可以在 PowerShell 中运行 `Get-FileHash .\DraftArena-<版本>-windows-x86_64.zip -Algorithm SHA256` 比对。

**Android（横屏，侧载安装，不上架应用商店）**：在手机浏览器中下载 `DraftArena-<版本>-android-arm64.apk`，打开后按提示允许“安装未知应用”即可安装。

- 系统要求：Android 5.0 及以上的 64 位（arm64-v8a）手机；支持 OpenGL ES 3.0。
- APK 使用本项目固定的发布密钥签名，后续版本可直接覆盖升级；如果提示“签名不一致”，说明文件不是从本仓库 Releases 获取的。
- Google Play 保护机制可能提示“未知开发者”，确认来源后选择“仍然安装”。
- 校验（可选）：`SHA256SUMS.txt` 同样包含 APK 的 SHA-256。

## 快速开始

```bash
python tools_setup_godot.py        # 下载引擎到 .tools/godot/
.tools/godot/godot.exe --path .    # 编辑器运行（或直接跑 godot_console.exe）
```

操作：WASD/手柄移动，攻击全自动，清怪攒经验升级三选一，ESC 暂停，F11 全屏。

手机（Android 横屏）：左半屏按住拖动即为虚拟摇杆，攻击全自动；右上角 II 暂停，系统返回键 = 暂停/继续（结算界面为重开，主菜单为退出）；选牌时点一下查看详情，再点同一张确认。

桌面预览手游版布局：`godot --path . -- --mobile-preview --safe-inset=96,0,48,40`（强制触屏模式与 expand，按屏幕像素模拟左/上/右/下安全区）。

## 代理协作

见 [AGENTS.md](AGENTS.md)——验收契约（smoke/sim/soak/shot 四件套）、编码约定、工作流。

## 文档

| 文档 | 内容 |
|---|---|
| [docs/GDD.md](docs/GDD.md) | 权威设计源：机制、数值表、39 张牌表、里程碑 |
| [docs/PROGRESS.md](docs/PROGRESS.md) | 进度日志（倒序，每次收工追加） |
| [docs/ART_SPEC.md](docs/ART_SPEC.md) | 美术规格与替换指南 |
| docs/INTEGRATION.md / docs/AUDIO_INTEGRATION.md | fx / audio 表现层接线 |

## 本地验收

统一入口（需要 PowerShell 7；CI 使用同一脚本）：

```bash
pwsh ./ci/run-tests.ps1                                   # 全部检查，默认使用 .tools/godot/godot_console.exe
pwsh ./ci/run-tests.ps1 -Quick                            # 跳过耗时的 soak
pwsh ./ci/run-tests.ps1 -Only boss-test,sim               # 只运行指定检查
pwsh ./ci/run-tests.ps1 -List                             # 列出全部检查项
pwsh ./ci/run-tests.ps1 -Godot /path/to/godot             # 指定其他 Godot 4.4.1 可执行文件（也可设环境变量 GODOT）
```

检查顺序：registry（确认 `scripts/tests/*_test.gd` 都已登记）→ import → smoke → boss-test → sawblade-test → spawn-curve-test → sim → soak。新增独立测试脚本时，要在 `ci/run-tests.ps1` 的检查清单或 `scripts/tests/boss_test_runner.gd` 中登记。

Linux 上可以先用 `GODOT_VERSION=4.4.1-stable GODOT_LINUX_SHA512=<见 tests-linux.yml> ./ci/install-godot-linux.sh` 下载 Godot（会校验官方 SHA-512），再运行 `pwsh ./ci/run-tests.ps1 -Godot .tools/godot-linux/godot`。CI 中的 `tests-linux` 工作流就是这样执行的。PR 上只跑快速模式（`-Quick`，不含 soak）；推送到 main、每日定时（03:17 北京时间）和手动触发时跑完整 soak。Windows 构建始终用快速模式。文档引用由 `python3 ci/check_doc_refs.py` 校验。

## 自动构建

push 到 main 自动打包 Windows exe（GitHub Actions，产物在 Actions 页 Artifacts）。

## 重建商店素材

```bash
python -m pip install -r requirements-tools.txt
python tools_build_store_assets.py
```

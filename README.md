# Draft Arena

Brotato 式短局肉鸽竞技场 + 经验升级选卡构筑。像素风，Godot 4.4.1，目标低价买断上架 Steam（先 Next Fest）。单人开发，agent 协作推进。

## 快速开始

```bash
python tools_setup_godot.py        # 下载引擎到 .tools/godot/
.tools/godot/godot.exe --path .    # 编辑器运行（或直接跑 godot_console.exe）
```

操作：WASD/手柄移动，攻击全自动，清怪攒经验升级三选一，ESC 暂停，F11 全屏。

## 代理协作

见 [AGENTS.md](AGENTS.md)——验收契约（smoke/sim/soak/shot 四件套）、编码约定、工作流。

## 文档

| 文档 | 内容 |
|---|---|
| [GDD.md](GDD.md) | 权威设计源：机制、数值表、39 张牌表、里程碑 |
| [PROGRESS.md](PROGRESS.md) | 进度日志（倒序，每次收工追加） |
| [ART_SPEC.md](ART_SPEC.md) | 美术规格与替换指南 |
| INTEGRATION.md / AUDIO_INTEGRATION.md | fx / audio 表现层接线 |

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

Linux 上可以先用 `GODOT_VERSION=4.4.1-stable GODOT_LINUX_SHA512=<见 tests-linux.yml> ./ci/install-godot-linux.sh` 下载 Godot（会校验官方 SHA-512），再运行 `pwsh ./ci/run-tests.ps1 -Godot .tools/godot-linux/godot`。CI 中的 `tests-linux` 工作流就是这样执行的。

## 自动构建

push 到 main 自动打包 Windows exe（GitHub Actions，产物在 Actions 页 Artifacts）。

## 重建商店素材

```bash
python -m pip install -r requirements-tools.txt
python tools_build_store_assets.py
```

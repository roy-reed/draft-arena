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

```bash
.tools/godot/godot_console.exe --headless --path . --import
.tools/godot/godot_console.exe --headless --path . -- --boss-test
.tools/godot/godot_console.exe --headless --path . --script res://scripts/tests/sawblade_cooldown_test.gd
.tools/godot/godot_console.exe --headless --path . --script res://scripts/tests/spawn_curve_test.gd
.tools/godot/godot_console.exe --headless --path . -- --smoke
.tools/godot/godot_console.exe --headless --path . -- --sim
.tools/godot/godot_console.exe --headless --path . -- --soak
```

## 自动构建

push 到 main 自动打包 Windows exe（GitHub Actions，产物在 Actions 页 Artifacts）。

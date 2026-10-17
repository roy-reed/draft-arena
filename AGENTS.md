# AGENTS.md — Draft Arena 代理协作契约

任何 coding agent（Claude Code / Codex / Cursor / ZCode…）进入本仓库，从本文件开始。改代码前先读完本文件与下方三份文档。

## 项目一句话

Brotato 式短局肉鸽竞技场 + 经验升级选卡构筑，像素风，Godot 4.4.1，目标低价买断上 Steam（先进 Next Fest）。单人开发（Roy，每周 2–4h），agent 负责代码推进，Roy 负责真人 playtest。

## 文档索引（权威顺序）

1. `docs/GDD.md` — 权威设计源：数值表、牌表（39 张）、机制规则。**改机制必须先读对应章节，改完同步更新。**
2. `docs/PROGRESS.md` — 进度日志（倒序，每次收工追加 ≤5 行）。**交付前必须追加。**
3. `docs/ART_SPEC.md` — 美术规格：`art/` 下 PNG 同名替换即换皮，生成器 `tools_gen_art.py`（纯标准库）。
4. `docs/INTEGRATION.md` / `docs/AUDIO_INTEGRATION.md` — fx.gd / audio.gd 接线参考。

## 环境引导（首次 clone 后）

```bash
python tools_setup_godot.py     # 自动下载 Godot 4.4.1 到 .tools/godot/（win/linux 自适应，约 50–150MB）
```

或手动从 godotengine.org releases 下载 4.4.1-stable。引擎不进仓库。

## 验收契约（硬规则，任何改动后必须执行）

```bash
# 以下 $GODOT 指可执行文件（.tools/godot/ 下）
$GODOT --headless --path . --import            # 必须零 SCRIPT ERROR / Parse Error
$GODOT --headless --path . -- --smoke          # 必须输出 SMOKE_OK（含购买/武器/卡池纯净/爆裂链式自检）
$GODOT --headless --path . -- --sim            # 必须输出 SIM_OK（经济不变量）
$GODOT --path . -- --shot                      # UI/视觉改动必跑：真实渲染截图存 AppData，人工或读图目视
```

- **SMOKE_OK 未全绿不许交付**，没有例外。smoke 会自动跳过存档落盘（`MetaS.persist` 开关），不会污染测试者存档。
- 超时判定：smoke 内置 180s，卡死会以 timeout 退出——运行卡死本身就是 bug。
- 已知噪音：headless 退出时的 RID/ObjectDB 告警是引擎固有现象，不算错。
- 只改文档/模板时（`*.md`、`docs/`、`store/`、Issue/PR 模板、标签目录）免跑 Godot，CI 只做文档引用检查。
- 云端 worker 没有 Godot 时：开草稿 PR，以 CI `tests-linux` 全绿作为 import/smoke/sim 证据；`--shot` 仍需本地真窗口，PR 里注明「待本地截图」。

## 编码约定

- GDScript 4.4，Tab 缩进，UTF-8 无 BOM，注释简体中文且克制（只写代码看不出的约束）。
- 单例模式：表现层库（fx.gd / audio.gd）= `class_name` + `static var I` + `enabled` 开关，smoke 下自动禁用。
- 命中判定全部距离制（无物理引擎）；子弹/回旋镖必须子步进防高速穿模。
- 敌人伤害入口有死亡守卫（`_dead`），击杀信号带位置与经验；新增伤害源勿绕过 `take_damage`。
- 数值常量集中在 `main.gd` 顶部（TIERS/WAVE_TIME/ELITE_CHANCE 等），`--sim` 与刷怪共用，改一处须同步。

## 多 agent 工作流

1. clone → 引导脚本 → `--import` + `--smoke`（先验基线全绿再动手）。
2. 按 GDD 章节/PROGRESS.md「下次目标」领任务；一次改动一个目标。
3. 交付 = 四件套全绿 + GDD 同步更新 + docs/PROGRESS.md 追加一行 + commit（信息写改动要点与验证结果）+ 按模板开 PR。
4. 不确定的设计决策不要拍板：在 PR「## 待 Roy 决策」写成勾选项（`- [ ] 同意：<建议方案>`），同时在 docs/PROGRESS.md 记「待 Roy 决策」，然后停下。

## GitHub 协作流程

- 分支 `<类型>/<简述>`（移动端用 `mobile/`）；PR 标题按 Conventional Commits（即 squash 后的提交标题），描述按 `.github/pull_request_template.md`。
- 自动标签（`ci/pr_hygiene.py`）：`size:S/M/L/XL`；改 CI、协作规则或发布配置加 `risk:L2`；「待 Roy 决策」有未勾选项加 `needs-decision`，全部勾选后自动移除。
- 测试分层：PR 上 tests-linux 跑快速模式，只改文档时跳过 Godot；Windows 只做导入 + 导出 + exe smoke；APK 仅在导出配置或 mobile 改动时导出；草稿 PR 不构建安装包；push main 全量，每日定时 soak。
- Roy 只做两件事：需要时试玩，决定合并。`risk:L2` 或 `needs-decision` 未处理不合并。
- 未经 Roy 明确同意不得：push main、force push、删分支、打 tag 或发布、改 secrets 或仓库设置、新增依赖。并行工作区只放 `.worktree/<名字>`（已在 .gitignore）。

## Code Review Rules

- 伤害与击杀：新增或修改伤害来源必须经过 `take_damage` 与 `_dead` 死亡守卫，高速弹体须子步进；可能重复结算击杀、经验或金币的路径按 P1 报告。
- 数值同步：改 `main.gd` 顶部常量或刷怪/经济逻辑时，`--sim` 须共用同一常量或函数，`docs/GDD.md` 对应数值须同步；不同步按 P1 报告。
- 存档与测试隔离：存档结构变化须兼容旧存档；smoke、sim 与测试脚本不得写入玩家存档（`MetaS.persist`）；违反按 P1 报告。

## 构建（可选，需先装导出模板）

```bash
$GODOT --headless --path . --export-release "Windows" ../dist/DraftArena.exe
```

export_presets.cfg 已配好（内嵌 PCK 单文件）。注意：目标 exe 被占用会导致 .tmp 重命名失败——先删旧文件再导出，核对时间戳。

## 当前状态

见 docs/PROGRESS.md 顶部。里程碑看 docs/GDD.md §6。永久卡死/需要 Roy 拍板的事项标注在 docs/PROGRESS.md。

# AUDIO_INTEGRATION — SFX 程序化音效接线说明

> 配套 `scripts/audio.gd`（`class_name SFX`）。模式与 fx.gd 完全一致：静态单例 + enabled 开关 + 静默 no-op。
> 本文档只描述接线方式，不改动任何宿主文件；集成后必须复跑 smoke（`godot --headless --path . -- --smoke`）验收。

## 1. 挂载点（main.gd _ready）

```gdscript
# 成员区，与 var fx: Node = null 并列：
var sfx: Node = null

# _ready() 内，紧跟 fx 的挂载：
sfx = SFX.new()
add_child(sfx)               # 顺序要求：先 add_child（_ready 里完成 I 赋值、音色合成、播放池构建）
SFX.I.enabled = not smoke    # 再置开关；smoke/headless 下所有调用静默，零副作用
```

- add_child 必须先于 enabled 赋值：`SFX.I` 在 `_ready`（由 add_child 触发）时才可用。
- 合成是同步的：11 个音效共约 6.2 万采样，毫秒级一次性开销，无异步加载，之后不重复合成。
- 全局类缓存：SFX 是新增 class_name，若首次运行报"SFX 未声明"，先跑一次 `godot --headless --path . --import`（或开一次编辑器）刷新全局类缓存；FX 已验证此机制可用。

## 2. API 速查

| 调用 | 说明 |
|---|---|
| `SFX.play("shoot")` | 播放，默认 ±5% 音高抖动；同名 40ms 内只播第一次（节流） |
| `SFX.play("kill", false)` | 第二参 false 关闭音高抖动（音色完全固定） |
| `SFX.set_volume(0.6)` | 0..1 线性音量，经 AudioServer 写 Master 总线，即时生效；v=0 走总线静音特判；不落盘 |
| `SFX.get_volume()` | 读取当前逻辑音量（float） |

音色 key 共 11 个：`shoot / hit / kill / hurt / pick / wave / boss / win / lose / click / dash`。未知 key 静默忽略。所有 API 在未挂载（I == null）或 enabled == false 时安全短路。

## 3. 建议接入点

| key | 位置 | 一行示例 | 备注 |
|---|---|---|---|
| shoot | `player.gd` `_shoot()`（match weapon_id 之后） | `SFX.play("shoot")` | 电弧/环刃分支提前 return，天然不发弹道音；散弹 3 连发只响一次（接在 _shoot 顶层） |
| kill | `enemy.gd` `take_damage()` 死亡分支（`if hp <= 0.0:` 内，`FX.death_burst` 旁） | `SFX.play("kill")` | 继承 enemy.gd 的喷吐者/首领与召唤小怪自动生效 |
| hurt | `player.gd` `take_damage()`（`FX.shake(5.0)` 附近） | `SFX.play("hurt")` | 无敌帧提前 return，天然限频 |
| pick | `main.gd` `_on_card_picked()`（state 校验通过后） | `SFX.play("pick")` | smoke 自动选牌时 enabled == false，静默 |
| wave | `main.gd` `_wave_cleared()`（金币结算后） | `SFX.play("wave")` | 首领波清完进下一区域也会响；若嫌与 win 叠加，可移到非首领分支 |
| boss | `main.gd` `_start_wave()`（`_spawn_boss()` 成功返回后） | `SFX.play("boss")` | 三种首领共用一次触发，位于 main 侧无需区分类型 |
| win / lose | `main.gd` `_finish()`（`ui.show_over` 之前） | `SFX.play("win" if result == "win" else "lose")` | 失败（"over"）与通关各一 |
| dash | `scripts/bosses/charge_boss.gd` `_physics_process()` "aim"→"dash" 切换处（`FX.shake(6.0)` 旁） | `SFX.play("dash")` | 冲锋起手；其他 Boss 若新增同类冲锋，可按语义状态接入 |
| click | `ui.gd` `_fire_cb()` 开头 + `_on_draft_pressed()` | `SFX.play("click")` | CanvasLayer 内直接静态调用，无需持有 SFX 引用 |

以上均为静态调用，任何脚本可直接使用，与 FX 的调用习惯一致。

## 4. 音量持久化建议（主流程负责，audio.gd 不落盘）

meta.json schema 增加 `"volume": float(0..1)`，缺省 0.8：

- `meta.gd` `default_data()`：加 `"volume": 0.8`
- `meta.gd` `load_data()`：加 `d["volume"] = clampf(float(parsed.get("volume", 0.8)), 0.0, 1.0)`（旧档缺字段自动回默认）
- `main.gd` `_ready()`：挂载 SFX 之后加载 `SFX.set_volume(float(meta_d.get("volume", 0.8)))`
- 写回：任一已调用 `MetaS.save_data` 的时机（如 `_finish`），或音量调节回调里 `meta_d["volume"] = SFX.get_volume()` 后统一 save_data

注意：SFX 的逻辑音量为静态保存，场景 `reload_current_scene`（按 R 重开）后新实例会在 `_ready` 里自动把音量重新应用到总线，无需主流程重复调用。

## 5. 已知限制

- **无 BGM**：纯短音效库。当前音量直接作用于 Master（总线 0）；未来加 BGM 建议独立总线，否则会被同一音量一起控制。
- **单总线**：set_volume 影响全部声音，没有 SFX/BGM 分轨。
- **池与节流**：10 个播放器 + 同名 40ms 节流，极端密集时最早起播的音会被抢占，属预期行为。
- **音色固定**：合成完全确定性（固定种子噪声），除播放时可选 ±5% pitch 抖动外无随机变化。
- **音质定位**：22050Hz / 16-bit / 单声道，贴合灰盒与复古风，非高保真。
- **未运行验证**：audio.gd 与本文档尚未经运行验证；由主代理集成后以 smoke 输出与真人 playtest 验收。

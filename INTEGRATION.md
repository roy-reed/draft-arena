# INTEGRATION.md — fx.gd 打击感库接线指南

`scripts/fx.gd`（`class_name FX`，Node 基类 + 静态单例 `FX.I`）。所有 API 为静态方法，
因有全局类名，任何脚本无需 preload 直接调用；未挂载（`FX.I == null`）或 `enabled == false`
时全部静默 no-op。挂载点唯一：main.gd。本文只描述接线方式，改动由主代理执行。

## 1. 挂载（main.gd，必做，其余全部依赖它）

```gdscript
# 顶部 const 区
const FXS := preload("res://scripts/fx.gd")
# 成员区
var fx: Node = null
# _ready() 末尾（在 smoke 分支判定之后、_menu_start() 之后）
fx = FXS.new()
add_child(fx)
FX.I.enabled = not smoke
```

- 顺序要求：`add_child` 会同步触发 `fx._ready()`（赋值 `FX.I`），因此必须在其之后设置 `enabled`。
- 也可省略 preload 常量，直接 `fx = FX.new()`，效果相同。
- 按 R 重开走 `reload_current_scene()`：旧 main 连同 fx 释放（`_exit_tree` 里 `I` 置空并恢复
  time_scale），新 main 挂载后 `I` 重新赋值，无需额外处理。

## 2. 接入点清单

| # | 文件.函数 | API | 作用 |
|---|---|---|---|
| 1 | player.gd `take_damage` | `shake(5.0)` `hit_stop(0.05)` `hurt_vignette()` | 玩家受击三连反馈 |
| 2 | enemy.gd `take_damage` | `hit_spark` `float_number` `knockback` | 命中反馈（含精英/首领、spitter、召唤物） |
| 3 | enemy.gd `take_damage` 死亡分支 | `death_burst` | 死亡爆裂 + 小震 |
| 4 | boss.gd `_physics_process` aim→dash | `shake(6.0)` | 首领冲锋震屏 |
| 5 | ui.gd `show_draft` / `show_over` | `pop_in` | 面板弹入 |

### 1) player.gd · take_damage

在 `invuln = 0.6` 之后（受击确认时，无敌帧/死亡 early-return 已经过滤）插入：

```gdscript
FX.shake(5.0)
FX.hit_stop(0.05)
FX.hurt_vignette()
```

玩家受击自带 0.6s 无敌帧，大于 hit_stop 的 0.1s 冷却，每次受击都会触发顿帧。

### 2) enemy.gd · take_damage（命中反馈）

在 `hp -= amount` 之后、死亡分支（`if hp <= 0.0`）之前插入：

```gdscript
FX.hit_spark(position, Color(1.0, 0.9, 0.4))
FX.float_number(self, amount, is_elite)
if from != null:
	FX.knockback(self, (position - from.position).normalized())
```

- `is_elite` 作 big 参数：精英与首领出大号金色数字（boss.gd 已把 is_elite 置 true，自动生效）。
- 现有调用路径（玩家武器、荆棘反弹）`from` 均非空，判空只是保险。
- spark 位置想更贴近命中点可改为 `position + Vector2(0.0, -radius * 0.5)`。
- spitter / boss_* 继承 enemy.gd，此段自动生效，无需重复接入。

### 3) enemy.gd · 死亡爆裂

死亡分支内部、`killed.emit(coin)` 之前插入（必须在 emit 前，避免宿主已 queue_free）：

```gdscript
FX.death_burst(position, body_color)
```

首领、召唤物、smoke 假人共用 take_damage，自动获得爆裂 + shake(1.5)。

### 4) boss.gd · 冲锋起手

`_physics_process` 的 `"aim"` 分支里，`_state = "dash"` 赋值处：

```gdscript
_state = "dash"
_state_t = 0.55
FX.shake(6.0)
```

### 5) ui.gd · 面板弹入

```gdscript
# show_draft()：draft_center.visible = true 之后
FX.pop_in(draft_panel)
# show_over()：over_center.visible = true 之后
FX.pop_in(over_center)
```

- show_over 没有面板成员变量，直接弹 `over_center`（全屏容器，pivot 自动取中心），
  无需改 `_build_over`；若只想弹面板本身，可把 PanelContainer 存为成员再 pop。
- pop_in 每帧刷新 pivot_offset，面板首次显示时容器尺寸未定型也能在下一帧校正。

## 3. 击退宿主端假设（kb 字段）

`FX.knockback(host, dir)` 只做 `host.set("kb", host.get("kb") + dir * 130.0)`，要求宿主：

- 声明 `var kb := Vector2.ZERO`（enemy.gd 需新增；player.gd 不接也安全——字段不存在时
  `get("kb")` 返回 null，knockback 静默跳过，不会报错）；
- 在移动逻辑中消费并衰减，建议（enemy.gd `_physics_process`）：

```gdscript
position += dir * speed * slow_factor * delta + kb * delta
kb = kb.move_toward(Vector2.ZERO, 900.0 * delta)
```

- 130.0 为击退初速（px/s），900.0 为衰减加速度（px/s²），均可调。
- boss.gd 继承 enemy.gd 自动获得 kb；其 dash 用 `position +=` 直加，不受影响。

## 4. smoke 自测禁用

- 挂载后 `FX.I.enabled = not smoke`：enabled == false 时所有静态 API 首行短路——
  不创建任何节点、不改 `Engine.time_scale`、不动 main.position、不消耗随机数，
  headless 结果与未接入完全一致，接入点无需再写 `if not smoke` 判断。
- smoke 会把 `Engine.time_scale` 设为 6.0：hit_stop 的备份恢复机制本可正确还原 6.0
  （恢复到进入前的值，而非硬编码 1.0），但为保证确定性仍在 smoke 中整体禁用。

## 5. 行为与实现要点

- **shake**：trauma 累积（上限 9，每秒衰减 16），偏移 = trauma²×0.2 px，每帧施加到
  `get_parent().position`；基点在起震瞬间捕获，结束（含 `_exit_tree`）恢复原位。
  UI 是 CanvasLayer(layer 10) 不受父变换影响；游戏内距离判定全用局部坐标，不受影响。
  注意：起震后主流程若自行改 main.position，会被覆盖到「基点+偏移」，当前 main 不动自身位置，安全。
- **hit_stop**：`Engine.time_scale` 压至 0.05，用 `Time.get_ticks_msec` 计真实时间恢复
  （SceneTreeTimer 与 `_process` delta 都被 time_scale 缩放，不可用于计时）；真实时间 0.1s
  冷却防连续触发；恢复到进入前的 time_scale；`_exit_tree` 兜底恢复。
- **float_number**：Label `top_level` 按世界坐标定位（宿主上方 26px），0.5s 上浮 24px +
  渐隐，结束 `queue_free`；big 为 30 号金色字 + 6px 描边。
- **hit_spark / death_burst**：CPUParticles2D one_shot；不设 texture（4.4 无 texture 时
  渲染方块，契合灰盒风）；`finished` 信号 + 子 Timer 双重回收，绝不泄漏。
- **hurt_vignette**：自带 CanvasLayer(layer 8) 全屏红闪 ColorRect，alpha 0.25→0（0.35s），
  `MOUSE_FILTER_IGNORE` 鼠标穿透，位于 HUD(layer 10) 之下，实例复用不重建。
- 层级约定：世界粒子 z_index=20（敌人 3 / 玩家 5 之上），伤害数字 z_index=50。

## 6. 验证状态

本库按约束未运行 godot，未做运行时验证；API 行为依据 Godot 4.4 文档静态核对
（CPUParticles2D.finished / 无 texture 方块、CanvasItem.top_level 等）。
集成后请复跑 smoke：应输出 `SMOKE_OK` 且无脚本报错；手感数值（震幅、顿帧时长、
击退力度）待人工 playtest 后在 fx.gd 常量区调整。

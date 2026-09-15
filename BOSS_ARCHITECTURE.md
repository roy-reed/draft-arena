# Boss 可扩展架构契约

> 状态：实施基线。本文定义边界、迁移顺序和验收；架构迁移先恢复并锁定当前文档规定的
> 玩法数值，Issue #7 的新平衡数值另批实施。

## 1. 目标与原则

Boss 系统必须允许新增 Boss、双 Boss 或阶段机制、正式原画与动画，而不继续扩大
`main.gd` 的类型分支。结构迁移与 Issue #7 的平衡调整分开：先锁定技能时序、遭遇规则及
当前 GDD 数值，再调整攻击、生命、防御和移除激光，避免无法判断回归来自架构还是数值。
当前代码中由 `_ready()` 覆盖配置产生的错误不属于应保留的“等价行为”。

核心原则：

1. `main.gd` 只启动遭遇并接收结果，不识别具体 Boss 类型。
2. 运行时属性只在进入场景树前计算一次；`_ready()` 不再写战斗数值。
3. 单体行为属于 Boss，双生复活、胜负门禁和奖励属于遭遇。
4. 战斗逻辑只依赖稳定锚点和表现接口，不依赖贴图尺寸或像素坐标。
5. 配置使用有类型的 Resource 与 PackedScene，不使用脚本路径、动态 Dictionary 或反射注入。

## 2. 目标分层

```text
Main
  -> BossEncounterController       # 编排、成员名册、完成条件、奖励、HUD 快照
       -> BossDefinition           # 身份、场景、基础属性、奖励、显示信息
       -> BossScalingPolicy        # 区域/无尽/Issue #7 的纯数值计算
       -> BossBase                 # 生命周期、受伤/死亡、状态与表现事件
            -> ChargeBoss          # 单体状态机
            -> SpitterBoss         # 单体弹幕行为
            -> SummonerBoss        # 单体召唤行为
                 -> BossVisual     # 灰盒、静态图或动画的可替换表现层
```

职责边界：

| 模块 | 必须负责 | 禁止负责 |
|---|---|---|
| `BossDefinition` | ID、显示名、PackedScene、基础属性、奖励 | 运行时状态、回调、阶段计时 |
| `BossScalingPolicy` | 输入定义和遭遇上下文，返回新的运行时属性 | 修改 Resource、生成节点 |
| `BossBase` | 配置锁定、公共生命循环、状态/阶段信号、表现调用 | 双 Boss 胜负规则、全局查找 Main |
| Boss 子类 | 自己的移动、技能与状态机 | 写公共数值、直接控制 HUD/换图 |
| `BossEncounterController` | 生成、服务注入、成员死亡、复活规则、完成快照 | 具体技能实现、贴图细节 |
| `BossVisual` | 动画降级、朝向、锚点、预警表现 | 伤害判定、数值缩放、胜负规则 |

## 3. 稳定运行时契约

### 3.1 配置时序

Boss 必须按以下固定顺序创建：

1. Encounter 从 `BossDefinition` 实例化 `PackedScene`。
2. ScalingPolicy 生成独立的 `BossRuntimeStats`。
3. Encounter 调用 `boss.configure(context, stats, services)`。
4. `configure()` 校验必需服务并锁定配置。
5. Encounter 设置位置、连接信号，再 `add_child()`。
6. `_ready()` 只建表现和启动状态机，不覆盖 HP、速度、攻击或奖励。

重复配置、未配置即入树、缺少必需服务都必须在 debug 构建中明确失败。`hp` 在配置时
与 `max_hp` 同步，因此普通生成、无尽生成和双生复活走同一条路径。

### 3.2 类型化数据

建议新增：

- `BossDefinition extends Resource`：`id`、`display_name`、`scene`、基础 HP/护甲/移速/
  接触伤害、奖励及 HUD 信息。
- `BossRuntimeStats extends RefCounted`：每次生成独立创建，不与定义共享可变状态。
- `BossEncounterContext extends RefCounted`：区域、无尽序号、竞技场和随机源。
- `BossServices extends RefCounted`：类型化 Callable，仅提供生成敌弹、生成随从等宿主能力。

行为专属参数留在具体 Boss 脚本的导出字段中。只有多个 Boss 共用且含义一致的参数才上移，
避免配置表与脚本成为两份真相源。

### 3.3 信号与交互

`BossBase` 至少发布：

- `health_changed(current, maximum)`：HUD 不再每帧读取 `boss_ref`。
- `state_changed(state_id)`：驱动动画、音效和可读性测试。
- `phase_changed(phase_id)`：为后续多阶段原画和机制保留稳定入口。
- `defeated(boss, reward)`：Encounter 统一处理名册、奖励和完成条件。

状态切换必须通过单一方法发生，以便同步动画、预警和测试记录；不得由外部直接修改
`_state`、计时器或 Boss 私有字段。

### 3.4 当前数值真相源

Issue #7 实施前，验收以 `GDD.md` 的“第九轮统一乘区”和区域定义为准，而不是以当前运行时
错误值为准：区域基础 HP 分别为 420、790、1400；全 Boss HP ×2、护甲 `base × 1.5 + 2`、
移速 ×1.2；区域 1 接触伤害再 ×2；普通奖励 15 金币，无尽奖励 25 金币。基础移速、接触
伤害和护甲来自 `BossDefinition`，乘区只存在于 `BossScalingPolicy`。

现状中 Boss 子类在 `_ready()` 写入移速等字段，且生成器在默认 20 HP 上先乘区、复活后再
覆盖 `max_hp`，会造成区域基础 HP 未生效、配置值被覆盖或复活时 `hp != max_hp`。迁移必须
将这些情况修复并建立回归测试，不能把它们当作旧行为继续复制。Issue #7 的 HP ×15、护甲
×5、攻击 ×3 和移除激光只替换策略/能力配置，不改变生命周期管线。

## 4. 遭遇与 Boss 的边界

区域 1 使用单成员遭遇；区域 2 使用 `TwinBossEncounter`，由遭遇控制 10 秒击杀窗口、
复活次数和完成门禁；区域 3 使用单成员遭遇。无尽模式只替换选择和缩放策略，不绕过
标准生成管线。

复活必须从同一个 `BossDefinition` 重新生成完整实例，并经过 ScalingPolicy；禁止先入树再
覆盖 `max_hp`。HUD 接收 Encounter 的成员快照，可稳定支持单条总血条、多个分段或阶段标记，
无需改变 Boss 行为代码。

## 5. 正式原画与动画兼容契约

每个 Boss 使用独立 `.tscn`，根节点挂行为脚本，至少提供：

```text
BossRoot
  VisualRoot
    Placeholder                 # 无正式素材时可见
    SpriteOrAnimatedSprite      # 可替换，不被战斗代码直接访问
    AnimationPlayer             # 可选
  Anchors
    Center
    ProjectileOrigin
    EffectOrigin
  TelegraphLayer
```

表现层支持统一语义 `idle`、`move`、`windup`、`attack`、`hurt`、`death`。缺少动画时静默
保持当前帧并继续战斗，不能因原画尚未到位而报错。攻击和特效只读取 Marker2D 的全局坐标；
禁止继续使用 `position + Vector2(14, -15)` 一类由某张贴图推导的魔法偏移。

替换静态图、AnimatedSprite2D、AnimationPlayer 或更大画布时，只允许修改 Boss 场景和
表现资源。逻辑半径继续使用明确的 gameplay radius，不从图片边界推导。

## 6. 最小评测契约

新增 `--boss-test`，直接实例化生产用 Boss 场景和 Encounter，不复制生产计算公式。固定随机
种子，失败返回非零退出码，并覆盖：

1. 每种 Boss 在配置后符合 3.4 的期望值，入树前后属性一致，`hp == max_hp`，`_ready()`
   不改运行时属性。
2. 普通、无尽和复活都经过同一缩放路径；定义 Resource 在运行后字节/字段不变。
3. 双生 Boss 首杀不完成遭遇，窗口内双杀完成，超时只复活缺失成员且为满血。
4. 必需锚点存在；无纹理、静态纹理和动画表现均不影响伤害与状态时序。
5. Encounter 完成只发一次，奖励只结算一次，释放后无遗留成员、弹体或预警节点。

每批变更还必须通过现有 `--import`、`--smoke`、`--sim`、`--soak` 和 `git diff --check`。
涉及表现时增加截图；涉及手感或巨大数值跨度时保留真人 playtest，自动测试不能替代它。

## 7. 迁移批次与停止条件

每批独立提交，前一批未绿不得进入下一批：

1. **基础层**：新增类型化定义、上下文、运行时属性、服务、BossBase 和测试入口；生产路径不切换。
2. **冲锋 Boss 试点**：建立首个独立场景和表现锚点；技能时序保持等价，数值达到 3.4 的
   文档期望值，已知生命周期错误必须转为通过用例。
3. **遭遇层**：引入 EncounterController，迁移区域 1，再迁移双生复活和 HUD 信号。
4. **其余 Boss**：迁移吐弹与召唤，消除 Main 的类型分支、回调字段和贴图坐标耦合。
5. **玩法变更**：单独实施 Issue #7 的数值乘区与移除激光，更新 GDD/PROGRESS 并真人验收。

任一批出现脚本错误、退出码非零、重复奖励、定义被修改、节点持续增长或基线案例回退，立即
停止，不在同一批继续叠加修补。

## 8. 协作分工

主代理负责接口取舍、基础类型与首个样板实现、差异审查和最终验收。执行 Harness 只接收
单批、逐文件的机械任务：创建已明确的资源/场景、搬迁已指定代码、运行完整命令矩阵并回传
原始输出；不得自行改接口、增加兼容补丁、批量重写旧文件或在失败后连续猜修。

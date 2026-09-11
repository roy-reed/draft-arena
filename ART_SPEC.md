# ART_SPEC.md — 像素美术规格与替换指南

当前 `art/` 下的 PNG 是**程序生成的占位图**（`tools_gen_art.py`，纯标准库可随时重新生成），
形状与灰盒多边形一一对应。替换正式美术时**保持同名覆盖**即可，代码零改动（`scripts/art.gd`
的 `ArtS.skin()` 按 `res://art/<name>.png` 探测，缺失时自动退回灰盒多边形）。

## 命名与尺寸（size = 逻辑像素，游戏内按 radius×2 等比缩放）

| 文件 | 尺寸 | 说明 |
|---|---|---|
| player_ranger.png | 24×24 | 游侠（蓝，兜帽+步枪） |
| player_brute.png | 24×24 | 蛮兵（橙，方壮+巨刃） |
| player_gunner.png | 24×24 | 炮手（黄，三角+双管） |
| enemy_chaser.png | 20×20 | 追击小怪（红，怒眼） |
| enemy_spitter.png | 20×20 | 吐弹小怪（紫菱，巨口） |
| boss_charge.png | 40×40 | 区域1 首领（冲锋型，双角） |
| boss_spitter.png | 40×40 | 区域2 首领（吐弹型，水晶） |
| boss_summoner.png | 40×40 | 区域3 首领（召唤型，法杖） |
| menu_bg.png | 320×180 | 菜单主视觉（竞技场+三角色+怪群+火把，游戏内 4x Nearest 放大） |
| floor_tile.png | 64×64 | 竞技场地砖（STRETCH_TILE 平铺，含网格线） |

## 硬性约定

- **透明背景 PNG，RGBA**；项目已设全局 Nearest 过滤（`project.godot` →
  `rendering/textures/canvas_textures/default_texture_filter=0`），按逻辑像素画即可保证锐利，
  不要预放大。
- 角色/小怪 16×16，首领 32×32；若做双帧动画（如 idle 两帧），改造成 `AnimatedSprite2D`
  前先与 GDD 对齐工作量——M2 只替换单帧。
- 调色板建议固定一套 ≤24 色（当前占位图用"主体+提亮+压暗+描边+白眼"五层），保证全图风格统一。
- 面向朝向：当前游戏无朝向翻转，素材画正面/对称即可；后续加翻转需在 skin 加载处镜像。

## 后续真实美术的三条路（M2/M3 决策）

1. 外包/自绘：按上表交付同名 PNG 覆盖。
2. AI 生成：注意 Steam 商店页需公示 AI 生成内容；像素一致性与去底需人工清理。
3. 素材包：注意授权与风格统一（调色板重映射到本项目五层结构）。

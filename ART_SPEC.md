# ART_SPEC.md — 像素美术规格与替换指南

`art/` 下的 3 张角色和 2 张小怪已在 M3-A 首批替换为 AI 母稿经人工筛选、透明裁切和定色量化后的正式候选图；
其余 PNG 仍是 `tools_gen_art.py` 生成的占位图。后续替换继续**保持同名覆盖**，代码零改动（`scripts/art.gd`
的 `ArtS.skin()` 按 `res://art/<name>.png` 探测，缺失时自动退回灰盒多边形）。不要再运行生成脚本覆盖已替换的 5 张图。

## 命名与尺寸（size = 逻辑像素，游戏内按 radius×2 等比缩放）

| 文件 | 尺寸 | 说明 |
|---|---|---|
| player_ranger.png | 24×24 | 游侠（蓝，兜帽+步枪） |
| player_brute.png | 24×24 | 蛮兵（橙，方壮+巨刃） |
| player_gunner.png | 24×24 | 炮手（黄，三角+双管） |
| enemy_chaser.png | 20×20 | 追击小怪（灰阶源图，运行时染红，怒眼） |
| enemy_spitter.png | 20×20 | 吐弹小怪（灰阶源图，运行时染紫，菱形+巨口） |
| boss_charge.png | 40×40 | 区域1 首领（冲锋型，双角） |
| boss_spitter.png | 40×40 | 区域2 首领（吐弹型，水晶） |
| boss_summoner.png | 40×40 | 区域3 首领（召唤型，法杖） |
| menu_bg.png | 320×180 | 菜单主视觉（竞技场+三角色+怪群+火把，游戏内 4x Nearest 放大） |
| floor_tile_r1.png / floor_tile_r2.png / floor_tile_r3.png | 64×64 | 三区域竞技场地砖（STRETCH_TILE 平铺，含网格线） |

## 硬性约定

- **透明背景 PNG，RGBA**；项目已设全局 Nearest 过滤（`project.godot` →
  `rendering/textures/canvas_textures/default_texture_filter=0`），按逻辑像素画即可保证锐利，
  不要预放大。
- 角色 24×24、小怪 20×20、首领 40×40；若做双帧动画（如 idle 两帧），改造成 `AnimatedSprite2D`
  前先与 GDD 对齐工作量——M2 只替换单帧。
- 调色板固定为 ≤24 色；M3-A 角色共用 19 色（深蓝描边、三套职业色、肤色、钢色），小怪只用 7 阶中性灰度，保留运行时六档难度染色。
- 面向朝向：当前游戏无朝向翻转，素材画正面/对称即可；后续加翻转需在 skin 加载处镜像。

## 剩余真实美术的三条路（M3）

1. 外包/自绘：按上表交付同名 PNG 覆盖。
2. AI 生成：注意 Steam 商店页需公示 AI 生成内容；像素一致性与去底需人工清理。
3. 素材包：注意授权与风格统一（调色板重映射到本项目五层结构）。

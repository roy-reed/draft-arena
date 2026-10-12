# -*- coding: utf-8 -*-
"""生成占位像素精灵（纯标准库，无第三方依赖）。
用法：python tools_gen_art.py（在项目根目录运行）
产物：art/*.png，由 scripts/art.gd 的 ArtS.skin() 加载（同名替换即换皮，见 docs/ART_SPEC.md）。
设计：三角色带专属武器特征（枪/刃/双管），敌人/首领各有轮廓辨识度，四层色阶+描边。
"""
import os
import struct
import zlib


def png_bytes(w, h, pixels):
    raw = b""
    for row in pixels:
        raw += b"\x00" + b"".join(struct.pack("4B", *px) for px in row)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


class C:  # 调色板：由基色生成 light/base/dark/outline 四层
    def __init__(self, base):
        self.base = base
        self.light = tuple(min(255, int(v * 1.45)) for v in base)
        self.dark = tuple(int(v * 0.6) for v in base)
        self.out = tuple(int(v * 0.22) for v in base)


STEEL = (168, 176, 190)
STEEL_D = (110, 118, 134)
WHITE = (244, 246, 250)
BLACK_I = (30, 28, 36)
HORN = (236, 226, 208)
GOLD = (244, 196, 88)


class Canvas:
    def __init__(self, size, h=None):
        self.size = size
        self.w = size
        self.h = h if h is not None else size
        self.px = [[None] * self.w for _ in range(self.h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, y0), min(self.h, y1 + 1)):
            for x in range(max(0, x0), min(self.w, x1 + 1)):
                self.set(x, y, c)

    def disc(self, cx, cy, r, c):
        for y in range(self.h):
            for x in range(self.w):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.set(x, y, c)

    def shade(self, pal, light_dir=(-1, -1), dark_dir=(1, 1)):
        # 边缘像素按方位提亮/压暗，其余保持基色
        solid = [[self.px[y][x] is not None for x in range(self.w)] for y in range(self.h)]

        def solid_at(x, y):
            return 0 <= x < self.w and 0 <= y < self.h and solid[y][x]

        for y in range(self.h):
            for x in range(self.w):
                if not solid[y][x]:
                    continue
                lx, ly = x + light_dir[0], y + light_dir[1]
                dx_, dy_ = x + dark_dir[0], y + dark_dir[1]
                if not solid_at(lx, ly):
                    self.px[y][x] = pal.out
                elif not solid_at(x - 1, y) or not solid_at(x, y - 1):
                    self.px[y][x] = pal.light
                elif not solid_at(x + 1, y) or not solid_at(x, y + 1):
                    self.px[y][x] = pal.dark
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is None:
                    self.px[y][x] = (0, 0, 0, 0)
                elif len(self.px[y][x]) == 3:
                    self.px[y][x] = self.px[y][x] + (255,)

    def out(self):
        rows = []
        for row in self.px:
            out_row = []
            for p in row:
                if p is None:
                    p = (0, 0, 0, 0)
                elif len(p) == 3:
                    p = (p[0], p[1], p[2], 255)
                out_row.append(p)
            rows.append(out_row)
        return rows


def eyes(cv, cx, cy, spread=3, pupil=True):
    for dx in (-spread, spread):
        cv.set(cx + dx, cy, WHITE)
        if pupil:
            cv.set(cx + dx, cy + 1, BLACK_I)


# ---- 玩家 24×24：身体 + 头部 + 专属武器 ----

def player_ranger():
    cv = Canvas(24)
    pal = C((70, 150, 235))
    cv.disc(11, 13, 7, pal.base)          # 身体
    cv.rect(8, 3, 14, 8, pal.base)        # 兜帽
    cv.rect(10, 5, 13, 7, pal.dark)       # 帽檐阴影
    cv.rect(9, 9, 13, 12, (238, 214, 176))  # 脸
    eyes(cv, 11, 10, 2)
    cv.rect(16, 11, 22, 12, STEEL)        # 步枪枪身
    cv.rect(21, 10, 23, 11, STEEL_D)      # 枪口
    cv.rect(14, 13, 16, 14, (120, 84, 50))  # 枪托
    cv.shade(pal)
    return cv.out()


def player_brute():
    cv = Canvas(24)
    pal = C((232, 120, 52))
    cv.rect(5, 7, 17, 19, pal.base)       # 方壮身体
    cv.rect(4, 7, 6, 11, pal.dark)        # 左肩甲
    cv.rect(16, 7, 18, 11, pal.dark)      # 右肩甲
    cv.rect(8, 2, 14, 7, pal.base)        # 头
    eyes(cv, 11, 5, 2)
    cv.set(11, 7, BLACK_I)
    for i, w in enumerate(range(4, 0, -1)):  # 巨刃（右下向右上）
        cv.rect(18 + i, 16 - i * 3, 18 + i, 16 - i * 3 + w, STEEL if i % 2 == 0 else STEEL_D)
    cv.rect(17, 15, 18, 18, (110, 74, 44))  # 刀柄
    cv.shade(pal)
    return cv.out()


def player_gunner():
    cv = Canvas(24)
    pal = C((240, 208, 76))
    for y in range(18, 4, -1):            # 三角身体
        half = (y - 5) // 2 + 3
        cv.rect(12 - half, y, 12 + half, y, pal.base)
    cv.disc(12, 6, 4, pal.base)           # 圆头
    eyes(cv, 12, 6, 2)
    cv.rect(16, 9, 23, 10, STEEL)         # 上枪管
    cv.rect(16, 12, 23, 13, STEEL)        # 下枪管
    cv.rect(21, 9, 23, 13, STEEL_D)       # 双枪口
    cv.rect(13, 10, 15, 12, (110, 74, 44))  # 枪身木托
    cv.shade(pal)
    return cv.out()


# ---- 敌人 20×20 ----

def enemy_chaser():
    # 中性灰白底图：游戏内按难度档位 modulate 染色（白绿蓝橙红金）
    cv = Canvas(20)
    pal = C((198, 200, 210))
    cv.disc(10, 11, 7, pal.base)
    cv.disc(10, 9, 5, pal.light)          # 背壳高光
    cv.rect(7, 9, 9, 10, WHITE)           # 怒眼
    cv.rect(12, 9, 14, 10, WHITE)
    cv.set(8, 10, BLACK_I)
    cv.set(13, 10, BLACK_I)
    cv.rect(9, 14, 12, 15, BLACK_I)       # 嘴
    cv.shade(pal)
    return cv.out()


def enemy_spitter():
    # 中性灰白底图：游戏内按难度档位 modulate 染色
    cv = Canvas(20)
    pal = C((192, 196, 208))
    for y in range(20):                   # 菱形身体
        d = abs(y - 10)
        cv.rect(10 - (9 - d), y, 10 + (9 - d), y, pal.base)
    cv.disc(10, 10, 4, pal.light)
    cv.set(9, 8, WHITE)
    cv.set(11, 8, WHITE)                  # 双眼
    cv.rect(8, 12, 12, 14, BLACK_I)       # 张开的嘴
    cv.set(10, 13, (90, 92, 104))         # 喉部
    cv.shade(pal)
    return cv.out()


# ---- 首领 40×40 ----

def boss_charge():
    cv = Canvas(40)
    pal = C((216, 62, 48))
    cv.disc(20, 22, 14, pal.base)
    cv.disc(17, 18, 8, pal.light)
    cv.rect(12, 16, 16, 19, WHITE)        # 大怒眼
    cv.rect(24, 16, 28, 19, WHITE)
    cv.rect(14, 17, 15, 19, BLACK_I)
    cv.rect(25, 17, 26, 19, BLACK_I)
    cv.rect(16, 27, 24, 30, BLACK_I)      # 大嘴
    for i in range(5):                    # 双角
        cv.set(11 + i, 9 - i, HORN)
        cv.set(12 + i, 9 - i, HORN)
        cv.set(28 - i, 9 - i, HORN)
        cv.set(27 - i, 9 - i, HORN)
    cv.shade(pal)
    return cv.out()


def boss_spitter():
    cv = Canvas(40)
    pal = C((160, 84, 224))
    for y in range(38):                   # 菱形巨躯
        d = abs(y - 20)
        half = 17 - d if d < 17 else 0
        cv.rect(20 - half, y + 1, 20 + half, y + 1, pal.base)
    cv.disc(20, 20, 7, pal.light)
    cv.rect(16, 15, 23, 18, WHITE)        # 独眼带
    cv.rect(19, 15, 20, 18, BLACK_I)
    cv.rect(15, 25, 25, 29, BLACK_I)      # 巨口
    cv.set(20, 27, (255, 120, 140))
    for i in range(6):                    # 头顶水晶
        h = 4 if i in (1, 4) else 3
        cv.rect(13 + i * 3, 3, 14 + i * 3, 2 + h, pal.light)
    cv.shade(pal)
    return cv.out()


def boss_summoner():
    cv = Canvas(40)
    pal = C((72, 186, 108))
    cv.disc(20, 22, 13, pal.base)         # 兜帽躯干
    cv.rect(13, 8, 27, 14, pal.base)      # 帽
    cv.rect(16, 9, 24, 13, BLACK_I)       # 帽内阴影脸
    cv.set(17, 11, (140, 255, 180))       # 发光双眼
    cv.set(22, 11, (140, 255, 180))
    cv.rect(9, 30, 31, 33, pal.dark)      # 袍底
    cv.rect(33, 6, 34, 30, (110, 74, 44))  # 法杖杆
    cv.disc(34, 5, 3, GOLD)               # 法杖宝珠
    cv.set(34, 4, WHITE)
    cv.shade(pal)
    return cv.out()


def blit(dst, src, ox, oy, scale=1):
    """把 src 画布贴到 dst 上（跳过透明像素），支持整数倍 nearest 放大"""
    for y in range(len(src)):
        for x in range(len(src[0])):
            p = src[y][x]
            if p[3] == 0:
                continue
            for dy in range(scale):
                for dx in range(scale):
                    dst.set(ox + x * scale + dx, oy + y * scale + dy, p)


def hline_band(cv, y0, y1, c):
    cv.rect(0, y0, cv.size - 1, y1, c)


def menu_bg():
    """320×180 菜单主视觉：竞技场 + 三角色 + 怪群剪影 + 火把；游戏内 Nearest 4x 放大"""
    cv = Canvas(320, 180)
    SKY1, SKY2 = (18, 16, 30), (30, 24, 46)
    FLOOR1, FLOOR2 = (46, 40, 60), (40, 34, 54)
    hline_band(cv, 0, 96, SKY1)
    hline_band(cv, 97, 118, SKY2)
    # 观众席剪影（两排）
    import random as _r
    rng = _r.Random(7)
    for row, y in enumerate((92, 100)):
        x = 6
        while x < 314:
            w = rng.randint(2, 4)
            h = rng.randint(3, 5)
            c = (24, 20, 36) if row == 0 else (34, 28, 50)
            cv.rect(x, y - h, x + w, y, c)
            x += w + rng.randint(1, 3)
    # 地面（横带 + 透视竖线）
    hline_band(cv, 119, 179, FLOOR1)
    for gy in range(119, 180, 12):
        cv.rect(0, gy, 319, gy, FLOOR2)
    for gx in range(40, 320, 60):
        top, bottom = 119, 179
        for y in range(top, bottom):
            t = (y - top) / (bottom - top)
            x = int(gx + (gx - 160) * 0.35 * t)
            if 0 <= x < 320:
                cv.set(x, y, FLOOR2)
    # 怪群剪影（暗红圆点，两层）
    for i in range(26):
        x = 8 + (i * 23 + rng.randint(0, 8)) % 300
        y = 128 + (i % 3) * 9 + rng.randint(0, 3)
        r = rng.choice((2, 3, 3, 4))
        cv.disc(x, y, r, (74, 30, 38))
        cv.set(x, y - r, (96, 40, 48))
    # 三角色（2x 放大贴入，站位错落）
    blit(cv, player_ranger(), 84, 96, 2)
    blit(cv, player_brute(), 148, 88, 2)
    blit(cv, player_gunner(), 212, 96, 2)
    # 火把（左右柱 + 火焰 + 座）
    for tx in (18, 296):
        cv.rect(tx, 70, tx + 3, 128, (70, 52, 40))
        cv.rect(tx - 2, 126, tx + 5, 132, (52, 44, 60))
        cv.disc(tx + 1, 64, 4, (240, 140, 60))
        cv.disc(tx + 1, 62, 2, (250, 200, 90))
        cv.set(tx + 1, 58, (255, 240, 160))
    # 顶部与底部暗角（用半透明黑覆盖）
    for y in range(0, 24):
        a = int(150 * (1 - y / 24))
        for x in range(320):
            px = cv.px[y][x]
            cv.px[y][x] = (int(px[0] * (1 - a / 255)), int(px[1] * (1 - a / 255)), int(px[2] * (1 - a / 255)), 255)
    return cv.out()


def floor_tile(base_a, base_b, grid):
    """64×64 地砖工厂：双色棋盘 + 噪点 + 右/下边缘网格线（游戏内 STRETCH_TILE 平铺）"""
    import random as _r
    rng = _r.Random(11)
    cv = Canvas(64)
    A, B = base_a, base_b
    for y in range(64):
        for x in range(64):
            base = A if ((x // 32) + (y // 32)) % 2 == 0 else B
            n = rng.randint(-3, 3)
            cv.px[y][x] = (max(0, base[0] + n), max(0, base[1] + n), max(0, base[2] + n), 255)
    for i in range(64):
        cv.set(63, i, grid)
        cv.set(i, 63, grid)
    for _ in range(26):
        x, y = rng.randint(1, 60), rng.randint(1, 60)
        cv.set(x, y, tuple(min(255, v + 10) for v in base_a))
    return cv.out()











SPRITES = [
    ("player_ranger", player_ranger),
    ("player_brute", player_brute),
    ("player_gunner", player_gunner),
    ("enemy_chaser", enemy_chaser),
    ("enemy_spitter", enemy_spitter),
    ("boss_charge", boss_charge),
    ("boss_spitter", boss_spitter),
    ("boss_summoner", boss_summoner),
    ("menu_bg", menu_bg),
    ("floor_tile_r1", lambda: floor_tile((26, 28, 40), (30, 32, 46), (52, 54, 74))),
    ("floor_tile_r2", lambda: floor_tile((24, 34, 28), (28, 40, 32), (50, 62, 52))),
    ("floor_tile_r3", lambda: floor_tile((42, 26, 32), (48, 30, 38), (70, 48, 56))),
]


def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "art")
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in SPRITES:
        px = fn()
        h = len(px)
        w = len(px[0])
        with open(os.path.join(out_dir, name + ".png"), "wb") as f:
            f.write(png_bytes(w, h, px))
        print("wrote", name, w, "x", h)


if __name__ == "__main__":
    main()

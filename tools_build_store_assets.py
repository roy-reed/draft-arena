#!/usr/bin/env python3
"""Build the frozen M3-B Steam artwork from the 12 shipped pixel-art assets.

The script deliberately creates no new gameplay art. It recomposes the existing
menu key art, character sprites, bosses, and floor tile into the current Steam
store and library dimensions using nearest-neighbour scaling only.

Install the pinned tool dependency first:
    python -m pip install -r requirements-tools.txt
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageEnhance, ImageOps


ROOT = Path(__file__).resolve().parent
ART = ROOT / "art"
STORE = ROOT / "store"

NEAREST = Image.Resampling.NEAREST

INK = (8, 9, 21, 255)
NAVY = (14, 17, 38, 255)
SLATE = (32, 36, 56, 255)
CYAN = (72, 202, 255, 255)
ORANGE = (255, 130, 54, 255)
GOLD = (255, 218, 72, 255)


GLYPHS = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "N": ("10001", "11001", "11001", "10101", "10011", "10011", "10001"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
}


def open_art(name: str) -> Image.Image:
    return Image.open(ART / name).convert("RGBA")


def alpha_over(base: Image.Image, overlay: Image.Image, xy: tuple[int, int] = (0, 0)) -> None:
    base.alpha_composite(overlay, dest=xy)


def fit_nearest(image: Image.Image, size: tuple[int, int], centering=(0.5, 0.5)) -> Image.Image:
    return ImageOps.fit(image, size, method=NEAREST, centering=centering)


def darken(image: Image.Image, factor: float) -> Image.Image:
    rgba = image.convert("RGBA")
    rgb = ImageEnhance.Brightness(rgba.convert("RGB")).enhance(factor)
    result = rgb.convert("RGBA")
    result.putalpha(rgba.getchannel("A"))
    return result


def add_top_shade(image: Image.Image, strength: int = 185, reach: float = 0.58) -> None:
    width, height = image.size
    shade = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shade)
    stop = max(1, int(height * reach))
    for y in range(stop):
        alpha = int(strength * (1.0 - y / stop) ** 1.7)
        draw.line((0, y, width, y), fill=(6, 7, 19, alpha))
    alpha_over(image, shade)


def add_vignette(image: Image.Image, strength: int = 120) -> None:
    width, height = image.size
    shade = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shade)
    bands = 18
    for index in range(bands):
        ratio = 1.0 - index / bands
        inset_x = int(width * 0.018 * index)
        inset_y = int(height * 0.018 * index)
        alpha = max(0, int(strength * ratio * ratio / bands * 2.1))
        draw.rectangle(
            (inset_x, inset_y, width - 1 - inset_x, height - 1 - inset_y),
            outline=(4, 5, 15, alpha),
            width=max(1, int(min(width, height) * 0.012)),
        )
    alpha_over(image, shade)


def glyph_pixels(lines: Iterable[str]) -> tuple[set[tuple[int, int]], dict[tuple[int, int], tuple[int, int, int, int]], int, int]:
    lines = tuple(lines)
    widths = []
    for line in lines:
        widths.append(sum(3 if char == " " else 6 for char in line) - (1 if line else 0))
    max_width = max(widths)
    pixels: set[tuple[int, int]] = set()
    colors: dict[tuple[int, int], tuple[int, int, int, int]] = {}
    for line_index, line in enumerate(lines):
        cursor = (max_width - widths[line_index]) // 2
        word_index = 0
        for char in line:
            if char == " ":
                cursor += 3
                word_index += 1
                continue
            color = CYAN if line_index == 0 and word_index == 0 else ORANGE
            for y, row in enumerate(GLYPHS[char]):
                for x, bit in enumerate(row):
                    if bit == "1":
                        point = (cursor + x, line_index * 10 + y)
                        pixels.add(point)
                        colors[point] = color
            cursor += 6
    return pixels, colors, max_width, len(lines) * 10 - 3


def render_logo(max_size: tuple[int, int], stacked: bool = False) -> Image.Image:
    lines = ("DRAFT", "ARENA") if stacked else ("DRAFT ARENA",)
    pixels, colors, text_width, text_height = glyph_pixels(lines)
    logical_width = text_width + 8
    logical_height = text_height + 8
    low = Image.new("RGBA", (logical_width, logical_height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(low)

    for x, y in pixels:
        draw.point((x + 6, y + 6), fill=(2, 3, 12, 180))

    outline: set[tuple[int, int]] = set()
    for x, y in pixels:
        for offset_y in (-1, 0, 1):
            for offset_x in (-1, 0, 1):
                outline.add((x + offset_x + 4, y + offset_y + 4))
    for point in outline:
        draw.point(point, fill=INK)
    for point in pixels:
        draw.point((point[0] + 4, point[1] + 4), fill=colors[point])

    accent_y = logical_height - 2
    accent_width = max(3, logical_width // 7)
    center = logical_width // 2
    draw.line((center - accent_width - 2, accent_y, center - 2, accent_y), fill=CYAN)
    draw.line((center + 2, accent_y, center + accent_width + 2, accent_y), fill=GOLD)

    max_width, max_height = max_size
    scale = max(1, min(max_width // logical_width, max_height // logical_height))
    return low.resize((logical_width * scale, logical_height * scale), NEAREST)


def place_logo(image: Image.Image, box: tuple[int, int, int, int], stacked: bool = False) -> None:
    left, top, right, bottom = box
    logo = render_logo((right - left, bottom - top), stacked=stacked)
    x = left + (right - left - logo.width) // 2
    y = top + (bottom - top - logo.height) // 2
    alpha_over(image, logo, (x, y))


def draw_pixel_frame(image: Image.Image, color=SLATE) -> None:
    width, height = image.size
    unit = max(2, min(width, height) // 96)
    length = unit * 10
    draw = ImageDraw.Draw(image)
    for x_sign, y_sign in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        x = unit * 4 if x_sign > 0 else width - unit * 4 - 1
        y = unit * 4 if y_sign > 0 else height - unit * 4 - 1
        draw.line((x, y, x + x_sign * length, y), fill=color, width=unit)
        draw.line((x, y, x, y + y_sign * length), fill=color, width=unit)


def make_wide(size: tuple[int, int], *, small: bool = False) -> Image.Image:
    menu = open_art("menu_bg.png")
    result = fit_nearest(menu, size, centering=(0.5, 0.58))
    result = darken(result, 0.83)
    if small:
        shade = Image.new("RGBA", size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(shade)
        for x in range(int(size[0] * 0.72)):
            alpha = int(190 * (1.0 - x / (size[0] * 0.72)) ** 0.55)
            draw.line((x, 0, x, size[1]), fill=(6, 7, 18, alpha))
        alpha_over(result, shade)
        place_logo(result, (int(size[0] * 0.035), int(size[1] * 0.18), int(size[0] * 0.63), int(size[1] * 0.82)))
    else:
        add_top_shade(result)
        place_logo(result, (int(size[0] * 0.10), int(size[1] * 0.035), int(size[0] * 0.90), int(size[1] * 0.37)))
    add_vignette(result)
    draw_pixel_frame(result)
    return result


def tiled_floor(size: tuple[int, int], top: int) -> Image.Image:
    width, height = size
    result = Image.new("RGBA", size, NAVY)
    tile = open_art("floor_tile_r1.png")
    for y in range(top, height, tile.height):
        for x in range(0, width, tile.width):
            result.alpha_composite(tile, dest=(x, y))
    return result


def pixel_glow(diameter: int, color: tuple[int, int, int, int]) -> Image.Image:
    low_size = 32
    low = Image.new("RGBA", (low_size, low_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(low)
    for radius, alpha in ((15, 18), (12, 26), (9, 38), (6, 54)):
        draw.ellipse(
            (16 - radius, 16 - radius, 16 + radius, 16 + radius),
            fill=(color[0], color[1], color[2], alpha),
        )
    return low.resize((diameter, diameter), NEAREST)


def paste_sprite(
    image: Image.Image,
    name: str,
    center: tuple[int, int],
    scale: int,
    *,
    opacity: int = 255,
) -> None:
    sprite = open_art(name)
    sprite = sprite.resize((sprite.width * scale, sprite.height * scale), NEAREST)
    if opacity != 255:
        alpha = sprite.getchannel("A").point(lambda value: value * opacity // 255)
        sprite.putalpha(alpha)
    alpha_over(image, sprite, (center[0] - sprite.width // 2, center[1] - sprite.height // 2))


def make_vertical(size: tuple[int, int]) -> Image.Image:
    width, height = size
    floor_top = int(height * 0.54)
    result = tiled_floor(size, floor_top)

    wall = fit_nearest(open_art("menu_bg.png").crop((0, 0, 320, 112)), (width, floor_top), centering=(0.5, 0.45))
    wall = darken(wall, 0.55)
    result.alpha_composite(wall, dest=(0, 0))

    boss_y = int(height * 0.15)
    boss_scale = max(2, width // 220)
    boss_centers = (int(width * 0.20), int(width * 0.50), int(width * 0.80))
    for name, center in zip(
        ("boss_charge.png", "boss_spitter.png", "boss_summoner.png"),
        boss_centers,
        strict=True,
    ):
        glow = pixel_glow(int(width * 0.26), ORANGE)
        alpha_over(result, glow, (center - glow.width // 2, boss_y - glow.height // 2))
        paste_sprite(result, name, (center, boss_y), boss_scale, opacity=188)

    place_logo(
        result,
        (int(width * 0.08), int(height * 0.28), int(width * 0.92), int(height * 0.57)),
        stacked=True,
    )

    hero_y = int(height * 0.78)
    hero_scale = max(5, width // 105)
    hero_centers = (int(width * 0.22), int(width * 0.50), int(width * 0.78))
    hero_data = (
        ("player_ranger.png", CYAN),
        ("player_brute.png", ORANGE),
        ("player_gunner.png", GOLD),
    )
    for (name, color), center in zip(hero_data, hero_centers, strict=True):
        glow = pixel_glow(int(width * 0.30), color)
        alpha_over(result, glow, (center - glow.width // 2, hero_y - glow.height // 2))
        paste_sprite(result, name, (center, hero_y), hero_scale)

    add_vignette(result, 145)
    draw_pixel_frame(result)
    return result


def make_library_hero(size: tuple[int, int]) -> Image.Image:
    # 480x155 scales exactly 8x to Steam's 3840x1240 hero target. Build a
    # dedicated text-free panorama so extending the 16:9 menu art does not
    # duplicate its characters at both edges.
    logical_size = (480, 155)
    floor_top = 91
    low = tiled_floor(logical_size, floor_top)

    wall_source = open_art("menu_bg.png").crop((0, 0, 320, 108))
    wall = fit_nearest(wall_source, (logical_size[0], floor_top), centering=(0.5, 0.5))
    low.alpha_composite(darken(wall, 0.58), dest=(0, 0))

    draw = ImageDraw.Draw(low)
    draw.rectangle((0, floor_top - 3, logical_size[0], floor_top + 2), fill=(7, 8, 20, 220))

    for name, center, opacity in (
        ("boss_charge.png", (64, 84), 174),
        ("boss_spitter.png", (240, 65), 92),
        ("boss_summoner.png", (416, 84), 174),
    ):
        glow = pixel_glow(92, ORANGE)
        alpha_over(low, glow, (center[0] - glow.width // 2, center[1] - glow.height // 2))
        paste_sprite(low, name, center, 2, opacity=opacity)

    for name, center, color in (
        ("player_ranger.png", (190, 121), CYAN),
        ("player_brute.png", (240, 121), ORANGE),
        ("player_gunner.png", (290, 121), GOLD),
    ):
        glow = pixel_glow(78, color)
        alpha_over(low, glow, (center[0] - glow.width // 2, center[1] - glow.height // 2))
        paste_sprite(low, name, center, 3)

    result = low.resize(size, NEAREST)
    add_vignette(result, 150)
    return result


def make_library_logo(size: tuple[int, int]) -> Image.Image:
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    place_logo(result, (20, 20, size[0] - 20, size[1] - 20))
    return result


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)
    with Image.open(path) as check:
        if check.size != image.size:
            raise RuntimeError(f"dimension mismatch for {path}: {check.size} != {image.size}")


def main() -> None:
    outputs = {
        STORE / "capsules" / "header.png": make_wide((920, 430)),
        STORE / "capsules" / "small.png": make_wide((462, 174), small=True),
        STORE / "capsules" / "main.png": make_wide((1232, 706)),
        STORE / "capsules" / "vertical.png": make_vertical((748, 896)),
        STORE / "library" / "library_capsule.png": make_vertical((600, 900)),
        STORE / "library" / "library_header.png": make_wide((920, 430)),
        STORE / "library" / "library_hero.png": make_library_hero((3840, 1240)),
        STORE / "library" / "library_logo.png": make_library_logo((1280, 300)),
    }
    for path, image in outputs.items():
        save(image, path)
        print(f"STORE_ASSET_OK {path.relative_to(ROOT).as_posix()} {image.width}x{image.height}")


if __name__ == "__main__":
    main()

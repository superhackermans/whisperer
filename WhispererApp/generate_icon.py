#!/usr/bin/env python3
"""Generate a cute Whisperer app icon (.icns) using Pillow.

Design: macOS rounded-rect with a warm purple-to-indigo gradient background,
a soft white speech bubble, and a stylized waveform inside the bubble.
Small sparkle accents for personality.

Output: AppIcon.icns (or AppIcon.png fallback) in the same directory.
"""

import math
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("Pillow not installed. Installing...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SIZE = 1024


def draw_rounded_rect(draw, bbox, radius, fill):
    """Draw a filled rounded rectangle."""
    x0, y0, x1, y1 = bbox
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.pieslice([x0, y0, x0 + 2 * radius, y0 + 2 * radius], 180, 270, fill=fill)
    draw.pieslice([x1 - 2 * radius, y0, x1, y0 + 2 * radius], 270, 360, fill=fill)
    draw.pieslice([x0, y1 - 2 * radius, x0 + 2 * radius, y1], 90, 180, fill=fill)
    draw.pieslice([x1 - 2 * radius, y1 - 2 * radius, x1, y1], 0, 90, fill=fill)


def lerp_color(c1, c2, t):
    """Linearly interpolate between two RGB(A) colors."""
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def create_icon(size):
    """Create the full icon at the given size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    corner_r = int(size * 0.22)

    # --- Background: purple-to-indigo diagonal gradient ---
    top_left = (130, 80, 220)     # warm purple
    top_right = (90, 120, 240)    # blue-purple
    bot_left = (160, 60, 200)     # magenta-purple
    bot_right = (60, 80, 200)     # deep indigo

    for y in range(size):
        ty = y / (size - 1)
        for x in range(size):
            tx = x / (size - 1)
            top = lerp_color(top_left, top_right, tx)
            bot = lerp_color(bot_left, bot_right, tx)
            c = lerp_color(top, bot, ty)
            draw.point((x, y), fill=(*c, 255))

    # Apply rounded-rect mask
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    draw_rounded_rect(mask_draw, [0, 0, size, size], corner_r, fill=255)
    img.putalpha(mask)

    # --- Speech bubble ---
    bubble_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bubble_layer)

    # Main bubble ellipse (slightly above center)
    bw = int(size * 0.62)
    bh = int(size * 0.46)
    cx, cy = size // 2, int(size * 0.44)
    bubble_box = [cx - bw // 2, cy - bh // 2, cx + bw // 2, cy + bh // 2]
    bubble_color = (255, 255, 255, 230)
    bd.ellipse(bubble_box, fill=bubble_color)

    # Speech bubble tail (small triangle at bottom-left)
    tail_x = cx - int(size * 0.08)
    tail_y = cy + bh // 2 - int(size * 0.04)
    tail_pts = [
        (tail_x - int(size * 0.04), tail_y),
        (tail_x + int(size * 0.06), tail_y),
        (tail_x - int(size * 0.10), tail_y + int(size * 0.14)),
    ]
    bd.polygon(tail_pts, fill=bubble_color)

    # Composite bubble onto icon
    img = Image.alpha_composite(img, bubble_layer)

    # --- Waveform bars inside bubble ---
    wave_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wave_layer)

    num_bars = 7
    bar_w = int(size * 0.038)
    bar_gap = int(size * 0.052)
    # Symmetric heights — taller in center for a nice arc
    heights = [0.10, 0.18, 0.28, 0.34, 0.28, 0.18, 0.10]
    total_w = num_bars * bar_w + (num_bars - 1) * bar_gap
    start_x = cx - total_w // 2
    wave_cy = cy  # vertically centered in bubble

    # Bar colors: gradient from purple to teal across the bars
    bar_colors = [
        (120, 60, 180),   # purple
        (100, 80, 200),
        (60, 120, 200),   # blue
        (40, 160, 180),   # teal
        (60, 120, 200),   # blue
        (100, 80, 200),
        (120, 60, 180),   # purple
    ]

    for i in range(num_bars):
        bx = start_x + i * (bar_w + bar_gap)
        bh_val = int(heights[i] * size)
        by_top = wave_cy - bh_val // 2
        by_bot = wave_cy + bh_val // 2
        r = bar_w // 2
        color = (*bar_colors[i], 220)
        wd.rounded_rectangle([bx, by_top, bx + bar_w, by_bot], radius=r, fill=color)

    img = Image.alpha_composite(img, wave_layer)

    # --- Sparkle accents ---
    sparkle_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sparkle_layer)

    def draw_sparkle(sx, sy, sr, color=(255, 255, 255, 180)):
        """Draw a 4-pointed star sparkle."""
        pts_v = [(sx, sy - sr), (sx - sr // 4, sy), (sx, sy + sr), (sx + sr // 4, sy)]
        pts_h = [(sx - sr, sy), (sx, sy - sr // 4), (sx + sr, sy), (sx, sy + sr // 4)]
        sd.polygon(pts_v, fill=color)
        sd.polygon(pts_h, fill=color)

    draw_sparkle(int(size * 0.18), int(size * 0.22), int(size * 0.04))
    draw_sparkle(int(size * 0.82), int(size * 0.18), int(size * 0.03), (255, 255, 255, 140))
    draw_sparkle(int(size * 0.78), int(size * 0.75), int(size * 0.025), (255, 255, 255, 120))

    img = Image.alpha_composite(img, sparkle_layer)

    return img


def main():
    print("Generating Whisperer app icon...")

    img = create_icon(SIZE)

    with tempfile.TemporaryDirectory() as tmpdir:
        iconset_dir = os.path.join(tmpdir, "AppIcon.iconset")
        os.makedirs(iconset_dir)

        # macOS iconutil expects: icon_NxN.png (1x) and icon_NxN@2x.png (2x)
        pairs = [(16, 32), (32, 64), (128, 256), (256, 512), (512, 1024)]
        for s1x, s2x in pairs:
            img.resize((s1x, s1x), Image.LANCZOS).save(
                os.path.join(iconset_dir, f"icon_{s1x}x{s1x}.png")
            )
            img.resize((s2x, s2x), Image.LANCZOS).save(
                os.path.join(iconset_dir, f"icon_{s1x}x{s1x}@2x.png")
            )

        icns_path = os.path.join(SCRIPT_DIR, "AppIcon.icns")

        try:
            subprocess.run(
                ["iconutil", "-c", "icns", iconset_dir, "-o", icns_path],
                check=True,
                capture_output=True,
            )
            print(f"Created {icns_path}")
        except FileNotFoundError:
            fallback_path = os.path.join(SCRIPT_DIR, "AppIcon.png")
            img.save(fallback_path)
            print(f"iconutil not available — saved PNG fallback at {fallback_path}")
        except subprocess.CalledProcessError as e:
            fallback_path = os.path.join(SCRIPT_DIR, "AppIcon.png")
            img.save(fallback_path)
            print(f"iconutil failed ({e.stderr.decode().strip()}) — saved PNG fallback at {fallback_path}")


if __name__ == "__main__":
    main()

# 生成应用图标：Android mipmap、Windows exe 图标与托盘图标。
#
# 设计意图：深青绿品牌底 + 白色播放三角 + 进度条，表达「自动播放课程进度」；
# 形状尽量简单，保证 16px 托盘尺寸下仍能认出。
#
# 用法：
#   python tool/generate_icons.py
#
# 依赖：Pillow（pip install pillow）。
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = 1024
SS = 4  # 超采样倍数，缩小时边缘更平滑

# 品牌色：与 lib/ui/theme.dart 的 sidebar / brand 保持一致。
TOP = (0x12, 0x3B, 0x36)
BOTTOM = (0x2E, 0x7D, 0x6F)


def build_master() -> Image.Image:
    size = OUT * SS
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 竖向渐变：先做 1x256 的渐变条，再放大，避免逐像素循环。
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        grad.putpixel(
            (0, y),
            (
                int(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
                int(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
                int(TOP[2] + (BOTTOM[2] - TOP[2]) * t),
            ),
        )
    grad = grad.resize((size, size))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=int(size * 0.225),
        fill=255,
    )
    canvas.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(canvas)
    # 播放三角：中心略偏上，给底部进度条留空间。
    cx, cy = size * 0.50, size * 0.455
    w, h = size * 0.30, size * 0.35
    d.polygon(
        [
            (cx - w * 0.45, cy - h * 0.50),
            (cx - w * 0.45, cy + h * 0.50),
            (cx + w * 0.55, cy),
        ],
        fill=(255, 255, 255, 255),
    )

    # 进度条：深色凹槽 + 白色已播放段。轨道如果用半透明白，
    # 在深绿底上会和填充混成一条白条，72% 的分段就看不出来了。
    bar_w, bar_h = size * 0.46, size * 0.062
    bx = (size - bar_w) / 2
    by = size * 0.735
    radius = bar_h / 2
    d.rounded_rectangle(
        [bx, by, bx + bar_w, by + bar_h],
        radius=radius,
        fill=(0, 0, 0, 70),
    )
    d.rounded_rectangle(
        [bx, by, bx + bar_w * 0.72, by + bar_h],
        radius=radius,
        fill=(255, 255, 255, 255),
    )

    return canvas.resize((OUT, OUT), Image.LANCZOS)


def main() -> None:
    icon = build_master()

    source = ROOT / "assets" / "icon.png"
    source.parent.mkdir(parents=True, exist_ok=True)
    icon.save(source)

    android = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in android.items():
        path = ROOT / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        icon.resize((px, px), Image.LANCZOS).save(path)

    # Windows exe / 快捷方式图标：多尺寸打进一个 ICO。
    icon.save(
        ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    # 托盘图标：小尺寸居多，16/20/24/32 是 Windows 实际会选的。
    icon.save(
        ROOT / "assets" / "tray.ico",
        sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48)],
    )

    print(f"已生成 {source}")
    print("已更新 Android mipmap、Windows app_icon.ico 与 assets/tray.ico")


if __name__ == "__main__":
    main()

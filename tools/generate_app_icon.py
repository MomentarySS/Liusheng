"""Generate 流声's pebble-and-wave launcher icons."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"

BG_CENTER = np.array([21, 101, 192], dtype=np.float64)  # #1565C0
BG_EDGE = np.array([13, 79, 140], dtype=np.float64)  # #0D4F8C
WAVE = (13, 79, 140, 255)
PEBBLE_TOP = np.array([250, 252, 255], dtype=np.float64)  # #FAFCFF
PEBBLE_BOTTOM = np.array([205, 229, 255], dtype=np.float64)  # #CDE5FF

# The waveform. Bars are mirrored about the canvas centre line (0.50) and the
# two side bars share a height, so the mark is symmetric on both axes. The 0.10
# stroke is what makes this survive the 16-24px the Windows notification area
# actually renders: the previous 0.058 stroke was 0.93px at 16px, and drawing
# five marks (two lead-in dots plus three bars) across that same 7.1px left
# 0.042px between them, so they merged into a single band. Three marks on a
# thicker stroke is the smallest change that stays legible.
BARS = ((0.32, 0.19), (0.50, 0.32), (0.68, 0.19))
WAVE_WIDTH = 0.10

ANDROID_LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
ANDROID_FOREGROUND = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}
# Windows picks the notification-area frame by display scale - 16px at 100%,
# 20px at 125%, 24px at 150%, 32px at 200% - so 20px belongs in the set.
ICO_SIZES = (16, 20, 24, 32, 48, 64, 128, 256)
ADAPTIVE_VISIBLE = 72 / 108  # Android masks adaptive icons to 72dp of 108dp.


def _gradient_field(size: int) -> Image.Image:
    """The bare diagonal brand gradient, without the rounded-square mask."""
    yy, xx = np.ogrid[:size, :size]
    t = np.clip(
        0.42 * xx / max(size - 1, 1) + 0.58 * yy / max(size - 1, 1),
        0,
        1,
    ) ** 1.05
    rgb = BG_CENTER * (1 - t[..., None]) + BG_EDGE * t[..., None]
    arr = np.concatenate(
        [rgb.astype(np.uint8), np.full((size, size, 1), 255, dtype=np.uint8)],
        axis=2,
    )
    return Image.fromarray(arr, "RGBA")


def _radial_background(size: int) -> Image.Image:
    field = _gradient_field(size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=size * 0.22,
        fill=255,
    )
    field.putalpha(mask)
    return field


def _adaptive_background(size: int) -> Image.Image:
    """Background layer for the Android adaptive icon.

    Android stretches the background layer across the whole 108dp canvas and
    then masks it down to the centre 72dp, so handing it the artwork verbatim
    would only ever show the middle third of the gradient. Pre-zoom by 108/72 so
    the region that survives the mask carries the same gradient range the
    legacy tile shows.
    """
    visible = int(size * ADAPTIVE_VISIBLE)
    offset = (size - visible) // 2
    field = _gradient_field(size)
    return field.crop((offset, offset, offset + visible, offset + visible)).resize(
        (size, size), Image.Resampling.LANCZOS
    )


def _cubic(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    samples: int,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for i in range(samples):
        t = i / (samples - 1)
        u = 1 - t
        points.append(
            (
                u**3 * p0[0]
                + 3 * u**2 * t * p1[0]
                + 3 * u * t**2 * p2[0]
                + t**3 * p3[0],
                u**3 * p0[1]
                + 3 * u**2 * t * p1[1]
                + 3 * u * t**2 * p2[1]
                + t**3 * p3[1],
            )
        )
    return points


# The stone outline was authored off-centre on both axes: about 3.3% right of
# the canvas centre (side margins 136px / 67px at 1024) and 17px low (top margin
# 183px / bottom 149px). A cubic bezier is affine in its control points, so
# shifting every control point by the same delta moves the rendered outline
# rigidly: the stone keeps its exact shape and only its placement changes.
PEBBLE_DX = -0.033
PEBBLE_DY = -0.0166

PEBBLE_CURVES = (
    ((0.50, 0.18), (0.38, 0.18), (0.28, 0.28), (0.20, 0.40)),
    ((0.20, 0.40), (0.13, 0.51), (0.10, 0.64), (0.18, 0.73)),
    ((0.18, 0.73), (0.27, 0.84), (0.43, 0.87), (0.58, 0.85)),
    ((0.58, 0.85), (0.76, 0.83), (0.91, 0.75), (0.93, 0.62)),
    ((0.93, 0.62), (0.96, 0.50), (0.87, 0.35), (0.78, 0.27)),
    ((0.78, 0.27), (0.69, 0.20), (0.59, 0.17), (0.50, 0.18)),
)


def _pebble_points(size: int) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for curve in PEBBLE_CURVES:
        points.extend(
            ((x + PEBBLE_DX) * size, (y + PEBBLE_DY) * size)
            for x, y in _cubic(*curve, samples=20)
        )
    return points


def _draw_pebble(canvas: Image.Image, size: int) -> None:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(_pebble_points(size), fill=255)

    yy, xx = np.mgrid[0:size, 0:size]
    t = np.clip(
        0.34 * xx / max(size - 1, 1) + 0.66 * yy / max(size - 1, 1),
        0,
        1,
    )[..., None]
    gradient = (PEBBLE_TOP * (1 - t) + PEBBLE_BOTTOM * t).astype(np.uint8)
    rgba = np.concatenate(
        [gradient, np.full((size, size, 1), 255, dtype=np.uint8)], axis=2
    )
    canvas.paste(Image.fromarray(rgba, "RGBA"), (0, 0), mask)


def _draw_waveform(draw: ImageDraw.ImageDraw, size: int) -> None:
    center_y = size * 0.50
    width = size * WAVE_WIDTH
    for x, height in BARS:
        h = size * height
        left = size * x - width / 2
        top = center_y - h / 2
        draw.rounded_rectangle(
            (left, top, left + width, top + h),
            radius=width / 2,
            fill=WAVE,
        )


def _render_art(size: int, *, background: bool) -> Image.Image:
    scale = 4 if size >= 48 else (3 if size >= 24 else 2)
    canvas_size = size * scale
    image = (
        _radial_background(canvas_size)
        if background
        else Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    )
    _draw_pebble(image, canvas_size)
    _draw_waveform(ImageDraw.Draw(image, "RGBA"), canvas_size)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def render(*, size: int, background: bool) -> Image.Image:
    if background:
        return _render_art(size, background=True)

    # Keep the adaptive foreground inside Android's mask-safe area.
    inner_size = max(int(size * 0.72), 2)
    inner = _render_art(inner_size, background=False)
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - inner_size) // 2
    output.alpha_composite(inner, (offset, offset))
    return output


def _save_ico(path: Path) -> None:
    images = [render(size=s, background=True).convert("RGBA") for s in ICO_SIZES]
    images[-1].save(
        path,
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=images[:-1],
    )


def main() -> None:
    BRANDING.mkdir(parents=True, exist_ok=True)
    render(size=1024, background=True).save(BRANDING / "app_icon.png", "PNG")
    render(size=1024, background=False).save(
        BRANDING / "app_icon_foreground.png", "PNG"
    )

    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, px in ANDROID_LEGACY.items():
        dest = res / folder
        dest.mkdir(parents=True, exist_ok=True)
        render(size=px, background=True).save(dest / "ic_launcher.png", "PNG")
    for folder, px in ANDROID_FOREGROUND.items():
        dest = res / folder
        dest.mkdir(parents=True, exist_ok=True)
        render(size=px, background=False).save(dest / "ic_launcher_foreground.png", "PNG")

    background = res / "drawable-nodpi"
    background.mkdir(parents=True, exist_ok=True)
    _adaptive_background(1024).convert("RGB").save(
        background / "ic_launcher_background.png", "PNG", optimize=True
    )

    # Two consumers, one design. windows/runner/resources/app_icon.ico is a
    # native build input read by Runner.rc and the Inno Setup script;
    # assets/branding/app_icon.ico is the Flutter asset that
    # lib/core/platform/desk_tray.dart loads. They stay separate files because
    # they are consumed separately, but they hold the same artwork.
    runner_ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    _save_ico(runner_ico)
    _save_ico(BRANDING / "app_icon.ico")
    print(f"Wrote {BRANDING / 'app_icon.png'}")
    print(f"Wrote {background / 'ic_launcher_background.png'}")
    print(f"Wrote {runner_ico}")
    print(f"Wrote {BRANDING / 'app_icon.ico'}")


if __name__ == "__main__":
    main()

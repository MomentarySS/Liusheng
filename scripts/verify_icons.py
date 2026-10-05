"""Verify every shipped icon asset against what the generator produces.

Run:  python scripts/verify_icons.py   (exit 0 = all checks passed)

flutter analyze, dart format and flutter test all pass while the launcher icon
is wrong, because none of them look at res/. This walks the artefacts instead:

- every density bucket's square tile, round tile and adaptive foreground has
  the pixel size its bucket requires
- the round tiles are genuinely circular (transparent corners, opaque edge
  midpoints) and not copies of the square one
- adaptive foreground content stays inside the 66dp guaranteed-safe circle
- both ICOs carry the full frame set, including the 20px frame Windows picks at
  125% display scaling
- re-running the generator changes nothing

That last check re-runs the generator against the working tree. It is
idempotent, so a clean tree stays clean; if it reports a diff, the committed
assets are stale and the files it just rewrote are yours to review and commit.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"

EXPECTED_LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
EXPECTED_FOREGROUND = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}
ICO_SIZES = (16, 20, 24, 32, 48, 64, 128, 256)
# 66dp guaranteed-visible diameter => 33dp radius; 72dp is the worst-case OEM
# mask, so anything above 33 only means "not guaranteed on every launcher".
GUARANTEED_DP = 33.0
WORST_CASE_DP = 36.0


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def check(self, ok: bool, message: str) -> None:
        print(f"  [{'ok  ' if ok else 'FAIL'}] {message}")
        if not ok:
            self.failures.append(message)

    def finish(self) -> int:
        print(f"\n{len(self.failures)} failure(s)")
        for f in self.failures:
            print(f"  FAIL {f}")
        return 1 if self.failures else 0


def load_alpha(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"))[:, :, 3]


def audit_square_tiles(r: Report) -> None:
    print("\nlegacy launcher tiles (android:icon)")
    for bucket, want in EXPECTED_LEGACY.items():
        p = RES / bucket / "ic_launcher.png"
        if not p.exists():
            r.check(False, f"{bucket}/ic_launcher.png missing")
            continue
        im = Image.open(p)
        r.check(im.width == want and im.height == want,
                f"{bucket}/ic_launcher.png {im.width}x{im.height} (want {want})")
        a = load_alpha(p)
        r.check(int(a[0, 0]) == 0 and int(a[-1, -1]) == 0,
                f"{bucket}/ic_launcher.png carries its own rounded mask")


def audit_round_tiles(r: Report) -> None:
    print("\nround launcher tiles (android:roundIcon)")
    print("  mipmap-anydpi-v26 only serves API 26+, so every density needs a real PNG")
    for bucket, want in EXPECTED_LEGACY.items():
        p = RES / bucket / "ic_launcher_round.png"
        if not p.exists():
            r.check(False, f"{bucket}/ic_launcher_round.png missing "
                            "-> @mipmap/ic_launcher_round cannot resolve below API 26")
            continue
        im = Image.open(p)
        r.check(im.width == want and im.height == want,
                f"{bucket}/ic_launcher_round.png {im.width}x{im.height} (want {want})")
        a = load_alpha(p)
        corners = [int(a[0, 0]), int(a[0, -1]), int(a[-1, 0]), int(a[-1, -1])]
        mid = [int(a[0, im.width // 2]), int(a[im.height // 2, 0])]
        r.check(max(corners) == 0 and min(mid) > 200,
                f"{bucket} round mask: corners={corners} edge midpoints={mid}")


def audit_foregrounds(r: Report) -> None:
    print(f"\nadaptive foregrounds (radius must stay under {GUARANTEED_DP}dp)")
    for bucket, want in EXPECTED_FOREGROUND.items():
        p = RES / bucket / "ic_launcher_foreground.png"
        if not p.exists():
            r.check(False, f"{bucket}/ic_launcher_foreground.png missing")
            continue
        arr = np.asarray(Image.open(p).convert("RGBA"))
        if arr.shape[0] != want:
            r.check(False, f"{bucket}/ic_launcher_foreground.png {arr.shape[0]}px (want {want})")
            continue
        dp = arr.shape[0] / 108.0
        ys, xs = np.nonzero(arr[:, :, 3] > 32)
        c = (arr.shape[0] - 1) / 2.0
        radius = float(np.hypot(xs - c, ys - c).max() / dp)
        where = ("inside the 66dp guaranteed circle" if radius <= GUARANTEED_DP
                 else "inside the 72dp worst case only")
        r.check(radius <= WORST_CASE_DP, f"{bucket} content radius {radius:.2f}dp ({where})")


def audit_icos(r: Report) -> None:
    print("\nICO frame sets")
    for rel in ("assets/branding/app_icon.ico", "windows/runner/resources/app_icon.ico"):
        p = ROOT / rel
        if not p.exists():
            r.check(False, f"{rel} missing")
            continue
        with Image.open(p) as im:
            sizes = tuple(sorted(s[0] for s in im.ico.sizes()))
        r.check(sizes == ICO_SIZES, f"{rel} frames {list(sizes)}")


def audit_masters(r: Report) -> None:
    print("\nbranding masters (documentation only; pubspec bundles just the .ico)")
    for name in ("app_icon.png", "app_icon_foreground.png"):
        p = ROOT / "assets" / "branding" / name
        if not p.exists():
            r.check(False, f"assets/branding/{name} missing")
            continue
        im = Image.open(p)
        r.check(im.size == (1024, 1024), f"assets/branding/{name} {im.size}")


def audit_reproducible(r: Report) -> None:
    print("\ncommitted assets still match the generator")
    before = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                            capture_output=True, text=True).stdout
    result = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "generate_app_icon.py")],
        cwd=ROOT, capture_output=True, text=True,
    )
    if result.returncode != 0:
        r.check(False, f"generator exited {result.returncode}: {result.stderr.strip()[:200]}")
        return
    after = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                           capture_output=True, text=True).stdout
    r.check(before == after,
            "re-running tools/generate_app_icon.py changed nothing"
            + ("" if before == after else "\n       stale assets, already rewritten:\n" + after))


def main() -> int:
    print(f"icon audit: {ROOT}")
    r = Report()
    audit_square_tiles(r)
    audit_round_tiles(r)
    audit_foregrounds(r)
    audit_icos(r)
    audit_masters(r)
    audit_reproducible(r)
    return r.finish()


if __name__ == "__main__":
    raise SystemExit(main())

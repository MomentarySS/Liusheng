"""Verify the packed artifacts actually carry the current icon artwork.

Run:  python scripts/verify_packaged_icons.py   (exit 0 = all checks passed)

Stale artefacts are invisible to every other gate: dart format, flutter analyze
and flutter test all stay green on a build that was packaged before the icon
changed, and a timestamp comparison is not proof because a rebuild can land in
the same minute. This compares content instead.

Two comparison rules, because the APK treats the two kinds of file differently:

- flutter_assets/ files are stored verbatim, so a byte comparison is exact.
- res/ files are re-encoded by aapt2, and AGP shortens their paths to
  res/Gc.png whether or not shrinkResources is on - so they can only be found
  by content, and aapt2 zeroes the RGB of fully transparent pixels. Compare
  the alpha channel everywhere and RGB only where alpha is non-zero.

The version is read from pubspec.yaml so this survives a release bump.
Artefacts that have not been built yet are skipped, not failed, so the check
is safe to run before pack.ps1.
"""

from __future__ import annotations

import io
import re
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
BUNDLED_SUFFIX = "flutter_assets/assets/branding/app_icon.ico"
ICO = ROOT / "assets" / "branding" / "app_icon.ico"
LEGACY = ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
ROUND = ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png"
FOREGROUND = ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png"


def current_version() -> str:
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([^\s+]+)", text, re.MULTILINE)
    if not m:
        raise SystemExit("could not read version from pubspec.yaml")
    return m.group(1).strip()


def pixels_equal(a: np.ndarray, ref: np.ndarray) -> bool:
    if a.shape != ref.shape:
        return False
    if not (a[:, :, 3] == ref[:, :, 3]).all():
        return False
    opaque = ref[:, :, 3] > 0
    return bool((a[:, :, :3][opaque] == ref[:, :, :3][opaque]).all())


def check(failures: list[str], ok: bool, message: str) -> None:
    print(f"  [{'ok  ' if ok else 'FAIL'}] {message}")
    if not ok:
        failures.append(message)


def skip(message: str) -> None:
    print(f"  [skip] {message}")


def verify_apk(path: Path, refs: dict[str, np.ndarray], ico: bytes, failures: list[str]) -> None:
    print(f"apk: {path.name}")
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        entry = next((n for n in names if n.endswith(BUNDLED_SUFFIX)), None)
        if entry is None:
            check(failures, False, f"no {BUNDLED_SUFFIX} in archive")
        else:
            blob = z.read(entry)
            check(failures, blob == ico,
                  f"bundled tray ico is current ({len(blob):,} bytes)")

        hits = {k: 0 for k in refs}
        for name in names:
            if not (name.startswith("res/") and name.endswith(".png")):
                continue
            try:
                a = np.asarray(Image.open(io.BytesIO(z.read(name))).convert("RGBA"), int)
            except Exception:
                continue
            for label, ref in refs.items():
                if pixels_equal(a, ref):
                    hits[label] += 1
        for label in ("launcher tile", "round tile", "adaptive foreground"):
            check(failures, hits[label] >= 1,
                  f"{label} present and current ({hits[label]} frame)")


def verify_zip(path: Path, ico: bytes, failures: list[str]) -> None:
    print(f"windows zip: {path.name}")
    with zipfile.ZipFile(path) as z:
        entry = next((n for n in z.namelist() if n.endswith(BUNDLED_SUFFIX)), None)
        if entry is None:
            check(failures, False, f"no {BUNDLED_SUFFIX} in archive")
            return
        blob = z.read(entry)
        check(failures, blob == ico, f"bundled tray ico is current ({len(blob):,} bytes)")


def main() -> int:
    version = current_version()
    print(f"packaged icon check: version {version}")

    apk = DIST / f"liusheng-{version}.apk"
    win = DIST / f"liusheng-windows-{version}.zip"

    if not apk.exists() and not win.exists():
        skip(f"no dist/liusheng-{version}.apk or dist/liusheng-windows-{version}.zip - "
             "nothing to check yet, run .\\scripts\\pack.ps1 after changing any icon")
        return 0

    ico = ICO.read_bytes()
    refs = {
        "launcher tile": np.asarray(Image.open(LEGACY).convert("RGBA"), int),
        "round tile": np.asarray(Image.open(ROUND).convert("RGBA"), int),
        "adaptive foreground": np.asarray(Image.open(FOREGROUND).convert("RGBA"), int),
    }
    failures: list[str] = []

    if apk.exists():
        verify_apk(apk, refs, ico, failures)
    else:
        skip(f"{apk.name} not built")

    if win.exists():
        verify_zip(win, ico, failures)
    else:
        skip(f"{win.name} not built")

    print(f"\n{len(failures)} failure(s)")
    for f in failures:
        print(f"  FAIL {f}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

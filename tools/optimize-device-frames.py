#!/usr/bin/env python3
"""Downscale over-resolution device frame PNGs to the largest size they are ever drawn at.

The bezel art in `screenshot/Assets.xcassets/DeviceFrames` is drawn by `DeviceFrameImageView`
as `Image(nsImage:).resizable()` into an explicit frame, and the screen aperture is placed purely
from the *fractions* on `DeviceFrameImageSpec`. So a PNG's pixel size is free to change:
the `frameWidth`/`frameHeight` declared in `DeviceFrameCatalogDefinitions.swift` are the authoring
reference the insets were measured against, NOT a claim about the shipped file. Leave them alone —
`DeviceFrame.baseDimensions` divides them by 6 for the default insert size of a new device shape.

Idempotent: a file already at or below its cap is skipped, so a second lanczos pass can never
degrade the art.

Usage:
    python3 tools/optimize-device-frames.py [--dry-run | --check]
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES_DIR = os.path.join(REPO_ROOT, "screenshot", "Assets.xcassets", "DeviceFrames")

# Long-edge cap in pixels, keyed by imageset stem. A frame is never drawn larger than the biggest
# canvas it can sit on: Mac presets top out at 2880x1800 (see Code/Models/ScreenshotSize.swift),
# and 2560 is 1:1 for a Mac occupying ~89% of that. Frames absent from this map already match
# their max canvas and are left at native size.
LONG_EDGE_CAP = {
    "imac24-silver-landscape": 2560,
    "macbookpro16-silver-landscape": 2560,
    "macbookpro14-silver-landscape": 2560,
    "macbookair13-midnight-landscape": 2560,
}


def png_dimensions(path):
    """Read width/height straight out of the IHDR chunk — no image library needed."""
    with open(path, "rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


def frame_pngs():
    for stem in sorted(os.listdir(FRAMES_DIR)):
        if not stem.endswith(".imageset"):
            continue
        name = stem[: -len(".imageset")]
        path = os.path.join(FRAMES_DIR, stem, f"{name}.png")
        if os.path.exists(path):
            yield name, path


def target_dimensions(width, height, cap):
    """Scale the long edge to `cap`, rounding the short edge to the nearest pixel."""
    scale = cap / max(width, height)
    if width >= height:
        return cap, round(height * scale)
    return round(width * scale), cap


def resize(path, width, height):
    fd, tmp = tempfile.mkstemp(suffix=".png", dir=os.path.dirname(path))
    os.close(fd)
    try:
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", path,
             "-vf", f"scale={width}:{height}:flags=lanczos",
             "-pix_fmt", "rgba", "-compression_level", "9", "-pred", "mixed", tmp],
            check=True,
        )
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--dry-run", action="store_true", help="print what would change")
    group.add_argument("--check", action="store_true",
                       help="fail if any frame exceeds its cap; write nothing")
    args = parser.parse_args()

    if not (args.dry_run or args.check) and not shutil.which("ffmpeg"):
        sys.exit("error: ffmpeg not found — install with: brew install ffmpeg")

    over_cap = []
    total_before = total_after = 0

    for name, path in frame_pngs():
        width, height = png_dimensions(path)
        size = os.path.getsize(path)
        total_before += size
        cap = LONG_EDGE_CAP.get(name)

        if cap is None or max(width, height) <= cap:
            total_after += size
            continue

        new_width, new_height = target_dimensions(width, height, cap)
        drift = abs((new_width / new_height) / (width / height) - 1) * 100
        over_cap.append(name)

        if args.check:
            print(f"over cap: {name} is {width}x{height}, cap {cap}")
            continue

        print(f"{name}: {width}x{height} -> {new_width}x{new_height} "
              f"({size / 1048576:.2f} MB, aspect drift {drift:.4f}%)")
        if args.dry_run:
            total_after += size
            continue

        resize(path, new_width, new_height)
        total_after += os.path.getsize(path)

    if args.check:
        if over_cap:
            sys.exit(f"{len(over_cap)} frame(s) exceed their cap — run tools/optimize-device-frames.py")
        print(f"all {len(list(frame_pngs()))} frames within cap")
        return

    if not over_cap:
        print("nothing to do — every frame is already within its cap")
        return

    print(f"\ntotal: {total_before / 1048576:.2f} MB -> {total_after / 1048576:.2f} MB")


if __name__ == "__main__":
    main()

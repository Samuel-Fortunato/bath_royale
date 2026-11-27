"""Deterministic Android exports from the approved PNG. Requires magick on PATH."""

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
BACKGROUND = "#25064B"
# Source-coordinate silhouette; excludes the baked rounded purple tile/white
# corners. The original PNG remains untouched. Revisit only for a new source.
OUTLINE = """M 627,50 C 583,50 581,107 611,116
L 537,196 Q 505,210 478,176 C 503,131 434,103 425,150
Q 416,180 446,186 L 478,286
C 352,280 331,310 332,346 L 337,374 L 350,387 L 374,556
C 299,542 236,588 226,640 C 215,687 243,714 277,710
L 290,779 Q 290,876 382,884 L 433,1006 L 437,1123
Q 440,1159 627,1163 Q 811,1159 818,1123 L 804,1094 L 794,1008
L 843,884 Q 934,880 950,796 L 970,711
C 1018,719 1040,677 1016,628 Q 986,552 880,556
L 907,388 L 918,376 L 921,345 Q 925,282 778,286
L 810,187 C 854,172 816,113 785,134 Q 767,154 781,176
Q 744,213 714,190 L 641,117 C 676,105 669,50 627,50 Z"""


def run(*args):
    subprocess.run(
        ["magick", "-define", "png:exclude-chunks=date,time", *map(str, args)],
        check=True,
    )


def generate(preview):
    source = ROOT / "assets/branding/app-icon.png"
    if not source.is_file():
        raise SystemExit(
            "Missing owner-supplied assets/branding/app-icon.png; no replacement generated"
        )
    if not shutil.which("magick"):
        raise SystemExit("magick missing; use nix develop .#branding")
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        mask, throne = work / "mask.png", work / "throne.png"
        run(
            "-size",
            "1254x1254",
            "xc:black",
            "-fill",
            "white",
            "-draw",
            "path '" + OUTLINE + "'",
            mask,
        )
        run(
            source,
            mask,
            "-alpha",
            "off",
            "-compose",
            "CopyOpacity",
            "-composite",
            "-trim",
            "+repage",
            throne,
        )
        for density, scale in (
            ("mdpi", 1),
            ("hdpi", 1.5),
            ("xhdpi", 2),
            ("xxhdpi", 3),
            ("xxxhdpi", 4),
        ):
            folder = RES / ("mipmap-" + density)
            folder.mkdir(parents=True, exist_ok=True)
            size = round(48 * scale)
            run(
                "-size",
                f"{size}x{size}",
                "xc:" + BACKGROUND,
                "(",
                throne,
                "-resize",
                f"x{round(44 * scale)}",
                ")",
                "-gravity",
                "center",
                "-compose",
                "over",
                "-composite",
                folder / "ic_launcher.png",
            )
            size = round(108 * scale)
            run(
                "-size",
                f"{size}x{size}",
                "xc:none",
                "(",
                throne,
                "-resize",
                f"x{round(64 * scale)}",
                ")",
                "-gravity",
                "center",
                "-compose",
                "over",
                "-composite",
                folder / "ic_launcher_foreground.png",
            )
            splash = RES / ("drawable-" + density)
            splash.mkdir(parents=True, exist_ok=True)
            run(
                "-size",
                f"{round(288 * scale)}x{round(288 * scale)}",
                "xc:none",
                "(",
                throne,
                "-resize",
                f"x{round(170 * scale)}",
                ")",
                "-gravity",
                "center",
                "-compose",
                "over",
                "-composite",
                splash / "splash_icon.png",
            )
        if preview:
            preview.mkdir(parents=True, exist_ok=True)
            for shape, path in (
                ("circle", "circle 108,108 108,0"),
                ("rounded-square", "roundrectangle 0,0 215,215 44,44"),
            ):
                run(
                    "-size",
                    "216x216",
                    "xc:black",
                    "-fill",
                    "white",
                    "-draw",
                    path,
                    work / "mask.png",
                )
                run(
                    "-size",
                    "216x216",
                    "xc:" + BACKGROUND,
                    "(",
                    throne,
                    "-resize",
                    "x192",
                    ")",
                    "-gravity",
                    "center",
                    "-compose",
                    "over",
                    "-composite",
                    work / "mask.png",
                    "-alpha",
                    "off",
                    "-compose",
                    "CopyOpacity",
                    "-composite",
                    preview / (shape + ".png"),
                )
    print("Android launcher/splash resources regenerated; source preserved.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview-dir", type=Path)
    generate(parser.parse_args().preview_dir)

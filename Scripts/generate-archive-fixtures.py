#!/usr/bin/env python3
"""Generate synthetic ZIP/RAR/7z archives; requires external rar and 7zz tools.

No private images are used. Large mode produces ~516 MiB and ~1026 MiB archives
with independent random PNG images (6 MiB each), including solid RAR and 7z.
Example: python3 Scripts/generate-archive-fixtures.py /tmp/Glint-Archives \
  --rar /path/to/rar --sevenzip /path/to/7zz --large
"""
import argparse
import os
from pathlib import Path
import struct
import subprocess
import zipfile
import zlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
parser.add_argument("--rar", required=True)
parser.add_argument("--sevenzip", required=True)
parser.add_argument("--large", action="store_true")
args = parser.parse_args()
root = args.directory.resolve()
images = root / "images"
images.mkdir(parents=True, exist_ok=True)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


width, height = (2048, 1024) if args.large else (120, 80)
count = 171 if args.large else 3
for i in range(count):
    # Independent random pixels defeat cross-image solid compression, keeping
    # archive size representative rather than a 1 GiB collection of duplicates.
    pixels = os.urandom(width * height * 3) if args.large else bytes([i * 80, 100, 200]) * width * height
    scanlines = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(scanlines, 1)) + chunk(b"IEND", b"")
    (images / (f"page{i:04}.png" if args.large else f"page{i+1:02}.png")).write_bytes(png)
if not args.large:
    (images / "café.png").write_bytes(png)
    (images / ".hidden.png").write_bytes(png)
    (images / "notes.txt").write_text("Ignored text file")
print(f"Generated {count} PNGs", flush=True)
for label, number in ([("512MiB", 86), ("1GiB", 171)] if args.large else [("small", count)]):
    names = [f"page{i:04}.png" for i in range(number)] if args.large else ["."]
    with zipfile.ZipFile(root / f"{label}.cbz", "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        for path in (images / name for name in names) if args.large else images.iterdir():
            archive.write(path, path.name)
    for solid in (True, False):
        suffix = "solid" if solid else "independent"
        rar = root / (f"{label}-{suffix}.rar" if args.large else f"{suffix}.rar")
        sevenzip = root / (f"{label}-{suffix}.7z" if args.large else f"{suffix}.7z")
        for path in (rar, sevenzip):
            if path.exists():
                path.unlink()
        subprocess.run([args.rar, "a", "-ma5", "-m1", "-md4m", "-s" if solid else "-s-", str(rar), *names],
                       cwd=images, check=True, stdout=subprocess.DEVNULL)
        subprocess.run([args.sevenzip, "a", "-t7z", "-mx=1", "-md=4m", "-ms=on" if solid else "-ms=off",
                        str(sevenzip), *names], cwd=images, check=True, stdout=subprocess.DEVNULL)
    print(f"Completed {label}", flush=True)

if not args.large:
    subprocess.run([args.sevenzip, "a", "-t7z", "-pglint-test", "-mhe=on", str(root / "encrypted.7z"), "."],
                   cwd=images, check=True, stdout=subprocess.DEVNULL)
    subprocess.run([args.rar, "a", "-hpglint-test", str(root / "encrypted.rar"), "."],
                   cwd=images, check=True, stdout=subprocess.DEVNULL)
    # RAR4 stored blocks with solid flags, generated independently of the readers.
    def rar_header(kind, flags, data):
        body = struct.pack("<BHH", kind, flags, 7 + len(data)) + data
        return struct.pack("<H", zlib.crc32(body) & 65535) + body
    rar = b"Rar!\x1a\x07\0" + rar_header(0x73, 8, b"\0" * 6)
    for i, path in enumerate(sorted(images.glob("*.png"))):
        data = path.read_bytes()
        name = path.name.encode()
        fields = struct.pack("<IIBIIBBHI", len(data), len(data), 3, zlib.crc32(data), 0, 20, 0x30, len(name), 0o100644)
        rar += rar_header(0x74, 0x8000 | (16 if i else 0), fields + name) + data
    rar += rar_header(0x7b, 0, b"")
    (root / "classic-solid.rar").write_bytes(rar)

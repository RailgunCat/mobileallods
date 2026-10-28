"""Convert the six selected desktop-theme CUR files to transparent PNGs.

Keep the source ZIPs under analysis/cursors/source. No theme is installed or run.
Source members, hashes and hotspots are recorded in the production manifest.
"""
from pathlib import Path
import hashlib
import json
import struct
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/data/hd/cursors"
SOURCE = ROOT / "analysis/cursors/source"


def decode(data):
    if len(data) < 22:
        raise ValueError("Truncated CUR header")
    reserved, kind, count = struct.unpack_from("<3H", data)
    if reserved != 0 or kind != 2 or count < 1:
        raise ValueError("Expected a Windows cursor")
    width, height, _, _, hotx, hoty, size, offset = struct.unpack_from("<4B2H2I", data, 6)
    width, height = width or 256, height or 256
    if offset < 6 + count * 16 or size < 40 or offset + size > len(data):
        raise ValueError("Invalid CUR image bounds")
    if hotx >= width or hoty >= height:
        raise ValueError("Cursor hotspot outside its image")
    dib = data[offset:offset + size]
    header, w, h, planes, bits, compression = struct.unpack_from("<IiiHHI", dib)
    if header != 40 or w != width or abs(h) != height * 2 or planes != 1 or compression != 0 or bits not in (1, 4, 8, 24, 32):
        raise ValueError("Unsupported cursor DIB")
    colors = struct.unpack_from("<I", dib, 32)[0] or ((1 << bits) if bits <= 8 else 0)
    if (bits <= 8 and colors > 1 << bits) or (bits > 8 and colors):
        raise ValueError("Invalid palette size")
    start = 40 + colors * 4
    stride = ((width * bits + 31) // 32) * 4
    mask_start = start + stride * height
    mask_stride = ((width + 31) // 32) * 4
    if mask_start + mask_stride * height > len(dib):
        raise ValueError("Truncated cursor bitmap/mask")
    palette = [tuple(dib[40 + i * 4:44 + i * 4]) for i in range(colors)]
    pixels = bytearray(width * height * 4)
    for y in range(height):
        sy = height - 1 - y if h > 0 else y
        row = dib[start + sy * stride:start + (sy + 1) * stride]
        for x in range(width):
            if bits <= 8:
                index = (row[(x * bits) // 8] >> (8 - bits - (x * bits) % 8)) & ((1 << bits) - 1)
                if index >= len(palette):
                    raise ValueError("Palette index outside table")
                b, g, r, _ = palette[index]
            else:
                b, g, r = row[x * (bits // 8):x * (bits // 8) + 3]
            mask = dib[mask_start + sy * mask_stride + x // 8] & (0x80 >> (x % 8))
            pixels[(y * width + x) * 4:(y * width + x + 1) * 4] = bytes((r, g, b, 0 if mask else 255))
    return width, height, pixels, [hotx, hoty]


def png(width, height, pixels):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    raw = b"".join(b"\0" + pixels[y * width * 4:(y + 1) * width * 4] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def main():
    manifest = json.loads((OUTPUT / "manifest.json").read_text(encoding="utf-8"))
    for kind, record in manifest.items():
        with zipfile.ZipFile(SOURCE / record["archive"]) as archive:
            data = archive.read(record["member"])
        if hashlib.sha256(data).hexdigest() != record["sha256"]:
            raise ValueError("Source hash mismatch: " + kind)
        width, height, pixels, hotspot = decode(data)
        if (width, height, hotspot) != (record["width"], record["height"], record["hotspot"]):
            raise ValueError("Source geometry mismatch: " + kind)
        (OUTPUT / (kind + ".png")).write_bytes(png(width, height, pixels))
    print("Prepared %d original cursors" % len(manifest))


if __name__ == "__main__":
    main()

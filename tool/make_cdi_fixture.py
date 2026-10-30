#!/usr/bin/env python3
"""Generate original CDI v3.5 test data; no commercial disc bytes are used.

Descriptor fields were located by byte-level experiments and checked with the
standalone CDIrip CLI. No converter or emulator implementation is referenced.
"""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1] / "test" / "fixtures"


def record(mode, size, start, pregap, count, variant=False):
    # Fixed offsets independently exercise the reader's sequential field parser.
    data = bytearray(236)
    data[4:24] = bytes.fromhex("000001000000ffffffff") * 2
    for offset, value in [
        (48, 0x80000000), (62, pregap), (66, count), (76, mode),
        (92, start), (96, pregap + count),
        (116, {2048: 0, 2336: 1, 2352: 2}[size]),
        (120, 0 if mode == 0 else 4), (154, 0xffffffff),
    ]:
        struct.pack_into("<I", data, offset, value)
    struct.pack_into("<H", data, 60, 2)
    if variant:
        struct.pack_into("<I", data, 154, 0)
        del data[158:]
        struct.pack_into("<I", data, 48, 0)
        del data[52:60]
    name = b"authored.bin"
    data[28] = len(name)
    data[29:29] = name
    if variant:
        struct.pack_into("<I", data, 0, 1)
        data[4:4] = bytes(8)
    return data


def sector(seed, number, size):
    return bytes((seed + number * 17 + i * 3) & 255 for i in range(size))


def make(name, sessions):
    payload = bytearray()
    descriptor = bytearray(struct.pack("<H", len(sessions)))
    for tracks in sessions:
        descriptor += struct.pack("<H", len(tracks))
        for mode, size, start, pregap, count, seed, variant in tracks:
            descriptor += record(mode, size, start, pregap, count, variant)
            for number in range(pregap + count):
                payload += sector(seed, number, size)
        descriptor += bytes(13)
    descriptor += struct.pack("<II", 0x80000006, len(descriptor) + 8)
    (ROOT / name).write_bytes(payload + descriptor)


if __name__ == "__main__":
    make("cdi_mode1.cdi", [[(1, 2048, 0, 2, 3, 7, False)]])
    make("cdi_sessions.cdi", [
        [(0, 2352, 0, 2, 3, 11, False),
         (1, 2048, 5, 1, 4, 29, True)],
        [(2, 2336, 45000, 2, 2, 47, False)],
    ])

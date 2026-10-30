"""Create original raw-subchannel fixtures using the CHD format's authoring tool."""

import argparse
from pathlib import Path
from random import Random
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
parser.add_argument("--codecs", nargs="+", default=["cdzl", "cdlz", "cdfl"])
args = parser.parse_args()
args.directory.mkdir(parents=True, exist_ok=True)
frames = []
for sector in range(80):
    rng = Random(sector)
    main = bytes(rng.randrange(256) if i % 32 < sector % 17 else sector
                 for i in range(2352))
    subcode = bytes((sector * 13 + i * 7) & 255 for i in range(96))
    frames.append(main + subcode)
(args.directory / "raw.bin").write_bytes(b"".join(frames))
(args.directory / "raw.toc").write_text(
    'CD_ROM\nTRACK MODE1_RAW RW_RAW\nDATAFILE "raw.bin" 00:00:00 00:01:05\n'
)
for codec in args.codecs:
    subprocess.run(["chdman", "createcd", "-i", str(args.directory / "raw.toc"),
                    "-o", str(args.directory / ("subcode_" + codec + ".chd")),
                    "-c", codec, "-np", "1", "-f"], check=True)

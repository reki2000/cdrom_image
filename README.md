# cdrom_image

Pure Dart reader for CUE, ISO, BIN, CDI and CHD CD-ROM images. Provides TOC and sector access through a caller-supplied `DiscFile` API. Storage backends are independent of image formats.

ISO 9660 file listing and extraction are not implemented.

## Supported formats

- CUE: multiple binary track files, audio/data tracks, `INDEX 00/01`, `PREGAP`, `POSTGAP` and `MODE1/2048`.
- ISO/BIN: single files with 2048 or 2352 bytes per sector.
- CDI v3.5: explicit sessions, mixed audio/data tracks, stored pregaps, raw 2352-byte sectors, cooked Mode 1/2048 and Mode 1/Mode 2 sectors stored without their 16-byte header (2336 bytes).
- CHD v5: chdman CD-ROM images using `cdlz`, `cdzl`, `cdfl` or `cdzs` (zstd). Reconstructs omitted sync/ECC bytes. Returns audio in BIN byte order.

Unsupported: parent CHDs, CHD v3/v4, non-CD-ROM CHDs and cooked CHD `MODE2_FORM1/FORM2` tracks.

## Usage

Implement `DiscFile` with `path`, `length()` and `read(offset, length)`. Paths must be relative to a common directory and use `/`. Concurrent reads must be independent. Local-file implementation:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cdrom_image/cdrom_image.dart';

class LocalDiscFile extends DiscFile {
  final File file;
  @override
  final String path;

  LocalDiscFile(this.file, this.path);

  @override
  Future<int> length() => file.length();

  @override
  Future<Uint8List> read(int offset, int length) async {
    final handle = await file.open(); // Separate handle for each read.
    try {
      await handle.setPosition(offset);
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }
}
```

Call `DiscImage.parse(file, files: candidates)`. For a CUE referencing `track.bin`, append this function to the implementation above:

```dart
Future<void> main() async {
  final cue = LocalDiscFile(File('example/images/disc.cue'), 'disc.cue');
  final bin = LocalDiscFile(File('example/images/track.bin'), 'track.bin');

  // Supply known references, or all candidate files.
  final (image, referenced) = await DiscImage.parse(cue, files: [bin]);
  print(referenced.map((file) => file.path)); // (track.bin)
  print(image.toc.tracks);

  final sectors = await image.readSectors(0, 1);
  print(sectors.first.length); // 2352
}
```

Set `files` to the known CUE references. If references are unknown, supply all candidate files, such as every file in the same directory. Image and candidate paths must share the same directory root. Unrelated candidates are ignored; the returned list contains only referenced files. Including the image file in `files` is optional.

For standalone ISO/BIN/CDI/CHD images, use `await DiscImage.parse(imageFile)`. Implement `DiscFile` for other storage backends, including browser files.

Run the [example](example/cdrom_image_example.dart) from the package root:

```sh
dart run example/cdrom_image_example.dart
```

The bundled `example/images/disc.cue` references `track.bin`, which contains two zero-filled Mode 1 payloads (2048 bytes each). This synthetic fixture contains no ISO 9660 filesystem.

## Sector contract and error handling

- CUE references: relative to the CUE file, case-insensitive, with `\` normalized to `/`. Paths outside the directory root are treated as missing files.
- LBA 0 corresponds to MSF 00:02:00.
- `readSectors(lba, count)`: returns 2352-byte sectors. Requires a nonnegative count and a range within `totalSectors`. `isReadable(lba)` checks a single LBA.
- Cooked Mode 1: expands 2048-byte payloads with sync and MSF/mode headers. EDC/ECC remain zero; output is not a bit-exact raw dump.
- Gaps: zero-filled sectors. CUE/ISO/BIN reads also zero-fill missing bytes at EOF. Read success does not verify source integrity.
- Raw CHD sectors: reconstruct ECC omitted by compression. Cooked Mode 1 expansion leaves EDC/ECC zero.
- Storage errors from `length()` and `read()` propagate to the caller.
- Invalid descriptions or missing CUE references: `DiscParseException`. Compressed-data errors may surface during sector reads.

## Raw subchannels

Images may also implement the optional `DiscSubcodeImage` interface.
`readSubcode(lba)` returns a copied 96-byte packed P-W record, without synchronization symbols, or null when the image does not retain full raw subchannels.
CHD RW_RAW tracks and stored pregaps provide those records; NONE, processed R-W-only tracks and synthetic gaps do not invent missing P-Q data.
Invalid sector ranges and storage/decompression errors use the same policy as sector reads.
The image package does not interpret Q CRC, positions or identifiers; consumers own that interpretation.

CD Deflate/LZMA/FLAC/Zstandard decompression retains the separate subchannel stream in each 2448-byte internal frame.
Tests use original synthetic cdzl/cdlz/cdfl fixtures made with chdman 0.242 and uncompressed layout/copy-ownership cases.
Generate those fixtures with `python3 tool/make_subcode_fixture.py OUTPUT_DIRECTORY`, then copy the resulting `subcode_*.chd` files into `test/fixtures/`.
The generator creates eighty original sectors and deterministic raw symbols; no copyrighted disc data are included.
The existing cdzs fixture checks zero-filled subchannels; independently generated nonzero cdzs coverage remains pending because the installed authoring tool does not support that codec.
The [CHD authoring-tool documentation](https://docs.mamedev.org/tools/chdman.html) describes the codec families; the tests compare output data without referring to external emulator source code.

## License

MIT. See [LICENSE](LICENSE).

## CDI descriptor validation and fixtures

CDI v3.5 support was developed from byte-level descriptor experiments, independently authored fixtures and the standalone CDIrip CLI as an opaque metadata/extraction oracle.
No converter or emulator implementation was used as a reference.
`tool/make_cdi_fixture.py` generates the original `cdi_mode1.cdi` and `cdi_sessions.cdi` files; `test/cdi_fixture.dart` supplies the same synthetic content without filesystem dependencies for browser tests.
The mixed fixture contains three tracks across two sessions, includes optional descriptor variants and mixes 2352, 2048 and 2336 bytes per stored sector.
CDIrip reports the same types, LBA values and lengths, and all extracted program bytes match the generated patterns.
`DiscToc.sessions` retains explicitly stored session numbers, first-track numbers and start LBAs; formats without decoded session metadata leave it null.
File-local pregaps are retained, the inaccessible initial negative-LBA pregap is omitted from the public sector range, and unrepresented logical gaps return zero sectors.
Mode 1/2048 expansion leaves EDC/ECC zero; 2336-byte sectors retain their stored bytes after a reconstructed sync/address/mode header.
Malformed descriptors, overlapping extents, payload-length mismatches and unsupported versions or encodings fail parsing rather than being reinterpreted as BIN.
CDI v2/v3, open sessions, index counts other than two, cooked Mode 2/2048, larger sector encodings and unrecognized descriptor variants remain unsupported.
The final disc-description block is not interpreted, and no raw subchannel or XA identity is inferred.

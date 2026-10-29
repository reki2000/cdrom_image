## Unreleased

- CHD v5 DVD images: 2048-byte sectors with the `zlib`, `lzma` and `zstd` codecs, read as one Mode 1 data track.
- The CHD hunk cache is sized by bytes.

## 0.1.0

- Initial release: CUE, ISO, BIN and CHD v5 CD-ROM images in pure Dart.
- Caller-supplied `DiscFile` storage, TOC access and 2352-byte sector reads by LBA.
- `DiscImage.parse(file, files: candidates)` with optional reference candidates.
- CUE support for multiple binary track files, audio/data tracks and gaps.
- CHD codecs: `cdlz`, `cdzl`, `cdfl` and `cdzs`, with sync/ECC reconstruction and BIN audio byte order.
- Parent CHDs, CHD v3/v4, non-CD-ROM CHDs and cooked CHD `MODE2_FORM1/FORM2` tracks are unsupported.

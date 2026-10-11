## 0.1.0

- Initial release: CUE, ISO, BIN and CHD v5 CD-ROM images in pure Dart.
- Caller-supplied `DiscFile` storage, TOC access and 2352-byte sector reads by LBA.
- `DiscImage.parse(file, files: candidates)` with optional reference candidates.
- CUE support for multiple binary track files, audio/data tracks and gaps.
- CHD codecs: `cdlz`, `cdzl`, `cdfl` and `cdzs`, with sync/ECC reconstruction and BIN audio byte order.
- Parent CHDs, CHD v3/v4, non-CD-ROM CHDs and cooked CHD `MODE2_FORM1/FORM2` tracks are unsupported.

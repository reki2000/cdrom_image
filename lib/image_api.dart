import 'dart:typed_data';

import 'filesystem_api.dart';
import 'format/parse.dart' as parser;

/// Disc image classification based on the file extension.
enum DiscFileKind {
  /// CUE, ISO, CHD or CDI image.
  image,

  /// BIN file, which may be a disc image or a ROM.
  maybeImage,

  /// Unrecognized image extension.
  notImage;

  /// Classifies [name] using a case-insensitive extension match.
  static DiscFileKind of(String name) =>
      switch (name.substring(name.lastIndexOf('.') + 1).toLowerCase()) {
        'cue' || 'iso' || 'chd' || 'cdi' => image,
        'bin' => maybeImage,
        _ => notImage,
      };
}

/// A track in the disc table of contents.
class DiscTrack {
  /// Track number, starting at 1.
  final int number;

  /// Whether the track contains CD audio rather than data.
  final bool isAudio;

  /// LBA of INDEX 01. LBA 0 corresponds to MSF 00:02:00.
  final int startLba;

  /// Sector count from this track's INDEX 01 to the next track's INDEX 01,
  /// or to the end of the disc for the last track.
  final int sectors;

  /// Creates a track entry.
  const DiscTrack(this.number, this.isAudio, this.startLba, this.sectors);

  @override
  String toString() =>
      "track $number ${isAudio ? "audio" : "data"} lba:$startLba sectors:$sectors";
}

/// An explicitly stored session boundary, without the two-second lead-in.
class DiscSession {
  final int number;
  final int firstTrack;
  final int startLba;

  const DiscSession(this.number, this.firstTrack, this.startLba);
}

/// Disc tracks and total sector count.
class DiscToc {
  /// Tracks in disc order.
  final List<DiscTrack> tracks;

  /// Number of sectors from LBA 0, excluding the initial 150-sector pregap.
  final int totalSectors;

  /// Null when the image format does not supply session metadata.
  final List<DiscSession>? sessions;

  /// Creates a table of contents.
  const DiscToc(this.tracks, this.totalSectors, {this.sessions});

  /// Empty table of contents.
  static const empty = DiscToc([], 0);
}

/// A description cannot be parsed or a referenced track cannot be resolved.
class DiscParseException implements Exception {
  /// Path of the image being parsed.
  final String imagePath;

  /// Description of the parse failure.
  final String message;

  /// Unresolved reference, when a CUE track file is missing.
  final String? referencedPath;

  /// Underlying parse error, when available.
  final Object? cause;

  /// Creates a parse failure with optional reference and cause information.
  const DiscParseException(this.imagePath, this.message,
      {this.referencedPath, this.cause});

  @override
  String toString() => 'DiscParseException: $imagePath: $message';
}

/// Format-independent access to a parsed CD-ROM image.
abstract interface class DiscImage {
  /// Byte length of each returned sector.
  static const sectorSize = 2352;

  /// Async factory for [file]. Optional [files] supply a .cue file's referenced
  /// tracks, with paths relative to a common directory. [file] need not be
  /// included in [files]. Supply known references or all candidate files;
  /// unrelated candidates are ignored. Files are iterated once to index paths.
  /// Standalone ISO, BIN, CDI and CHD images do not require [files].
  /// Returns the image and distinct referenced files, excluding [file].
  /// Standalone images have no referenced files.
  /// Throws [DiscParseException] for invalid descriptions or missing references.
  static Future<(DiscImage, List<DiscFile>)> parse(DiscFile file,
          {Iterable<DiscFile> files = const []}) =>
      parser.parse(file, files: files);

  /// Track layout and total sector count.
  DiscToc get toc;

  /// Number of sectors addressable from LBA 0.
  int get totalSectors;

  /// Whether [lba] lies within the disc's sector range.
  bool isReadable(int lba);

  /// Reads [count] 2352-byte sectors starting at [lba].
  /// The count must be nonnegative and the range must be inside [totalSectors].
  /// Cooked Mode 1 sectors are expanded with zero EDC/ECC fields.
  /// Gaps and missing bytes at EOF in CUE/ISO/BIN images are zero-filled.
  /// Storage and compressed-data errors propagate to the caller.
  Future<List<Uint8List>> readSectors(int lba, int count);
}

/// Optional capability for images that actually retain raw P-W subchannels.
abstract interface class DiscSubcodeImage {
  /// Reads 96 packed P-W symbols at [lba], excluding synchronization symbols.
  /// Returns null when the source has no full raw subchannels for this sector.
  /// Invalid LBAs and storage/decompression errors follow [DiscImage.readSectors].
  /// The returned bytes are independent of the image's internal cache.
  Future<Uint8List?> readSubcode(int lba);
}

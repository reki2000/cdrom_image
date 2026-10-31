import 'dart:typed_data';

import '../../filesystem_api.dart';
import '../../image_api.dart';
import '../file_image.dart';

/// DiscJuggler v3.5 layouts verified with independent CLI fixtures.
/// Unknown descriptor variants fail instead of falling back to raw BIN.
class CdiImage implements DiscImage {
  CdiImage._(this.file, this.toc, this._tracks);
  final DiscFile file;
  @override
  final DiscToc toc;
  final List<_Track> _tracks;

  static Future<CdiImage> open(DiscFile file) async {
    final length = await file.length();
    if (length < 10) throw const FormatException('Truncated CDI footer');
    final footer = await file.read(length - 8, 8);
    if (footer.length != 8) throw const FormatException('Truncated CDI footer');
    final words = ByteData.sublistView(footer);
    if (words.getUint32(0, Endian.little) != 0x80000006) {
      throw const FormatException('Unsupported CDI version (requires v3.5)');
    }
    final descriptorLength = words.getUint32(4, Endian.little);
    if (descriptorLength < 10 || descriptorLength > length) {
      throw const FormatException('Invalid CDI descriptor location');
    }
    final dataEnd = length - descriptorLength;
    // At most 99 tracks with byte-length names fit in this prefix. Disc-level
    // descriptive metadata after the session records is not interpreted.
    final available = descriptorLength - 8;
    final cursor = _Cursor(await file.read(dataEnd, available.clamp(0, 65536)));
    final sessionCount = cursor.word(2);
    if (sessionCount < 1 || sessionCount > 99) {
      throw const FormatException('Invalid CDI session count');
    }
    final tracks = <_Track>[], sessions = <DiscSession>[];
    var dataOffset = 0, previousEnd = 0;
    for (var session = 1; session <= sessionCount; session++) {
      final count = cursor.word(2);
      if (count < 1 || tracks.length + count > 99) {
        throw const FormatException(
            'Unsupported empty or oversized CDI session');
      }
      for (var index = 0; index < count; index++) {
        final prefix = cursor.word(4);
        if (prefix == 1) {
          cursor.skip(8);
        } else if (prefix != 0) {
          throw const FormatException('Unsupported CDI track prefix');
        }
        const marker = [0, 0, 1, 0, 0, 0, 255, 255, 255, 255];
        for (var copy = 0; copy < 2; copy++) {
          for (final byte in marker) {
            if (cursor.word(1) != byte) {
              throw const FormatException('Invalid CDI track marker');
            }
          }
        }
        cursor.skip(4);
        cursor.skip(cursor.word(1));
        cursor.skip(19);
        // This word is either a flag for eight more header bytes or a plain
        // value, such as 333,000 (a 74-minute capacity in sectors).
        if (cursor.word(4) == 0x80000000) cursor.skip(8);
        if (cursor.word(2) != 2) {
          throw const FormatException('Unsupported CDI index count');
        }
        final pregap = cursor.word(4), sectors = cursor.word(4);
        cursor.skip(6);
        final mode = cursor.word(4);
        cursor.skip(12);
        final start = cursor.word(4), stored = cursor.word(4);
        cursor.skip(16);
        final readMode = cursor.word(4);
        cursor.skip(34);
        final extension = cursor.word(4);
        if (extension == 0xffffffff) {
          cursor.skip(78);
        } else if (extension != 0) {
          throw const FormatException('Unsupported CDI track extension');
        }
        final size =
            switch (readMode) { 0 => 2048, 1 => 2336, 2 => 2352, _ => 0 };
        if (mode > 2 ||
            size == 0 ||
            (mode == 0 && size != 2352) ||
            (mode == 2 && size == 2048)) {
          throw const FormatException('Unsupported CDI sector encoding');
        }
        if (sectors == 0 ||
            stored != pregap + sectors ||
            (tracks.isNotEmpty && start - pregap < previousEnd) ||
            dataOffset + stored * size > dataEnd) {
          throw const FormatException('Invalid CDI track extent');
        }
        if (index == 0) {
          sessions.add(DiscSession(session, tracks.length + 1, start));
        }
        tracks.add(_Track(start, pregap, sectors, size, mode, dataOffset));
        previousEnd = start + sectors;
        dataOffset += stored * size;
      }
      cursor.skip(13);
    }
    if (dataOffset != dataEnd) {
      throw const FormatException('CDI payload length does not match tracks');
    }
    final toc = DiscToc([
      for (var i = 0; i < tracks.length; i++)
        DiscTrack(
            i + 1,
            tracks[i].mode == 0,
            tracks[i].start,
            (i + 1 < tracks.length ? tracks[i + 1].start : previousEnd) -
                tracks[i].start)
    ], previousEnd, sessions: List.unmodifiable(sessions));
    return CdiImage._(file, toc, tracks);
  }

  @override
  int get totalSectors => toc.totalSectors;
  @override
  bool isReadable(int lba) => lba >= 0 && lba < totalSectors;

  @override
  Future<List<Uint8List>> readSectors(int lba, int count) async {
    if (lba < 0 || count < 0 || lba + count > totalSectors) {
      throw RangeError('CDI sector range');
    }
    final result = <Uint8List>[];
    var position = lba;
    for (final track in _tracks) {
      final begin = track.start - track.pregap,
          end = track.start + track.sectors;
      if (position >= lba + count) break;
      if (end <= position) continue;
      while (position < begin && position < lba + count) {
        result.add(Uint8List(2352));
        position++;
      }
      if (position >= lba + count) break;
      final amount = (lba + count - position).clamp(0, end - position);
      final bytes = await file.read(
          track.offset + (position - begin) * track.size, amount * track.size);
      if (bytes.length != amount * track.size) {
        throw const FormatException('Truncated CDI sector payload');
      }
      for (var i = 0; i < amount; i++) {
        final stored =
            Uint8List.sublistView(bytes, i * track.size, (i + 1) * track.size);
        final sector = track.size == 2048
            ? FileImage.mode1Sector(stored, position + i)
            : track.size == 2352
                ? Uint8List.fromList(stored)
                : (FileImage.mode1Sector(Uint8List(2048), position + i)
                  ..[15] = track.mode
                  ..setAll(16, stored));
        result.add(sector);
      }
      position += amount;
    }
    while (result.length < count) {
      result.add(Uint8List(2352));
    }
    return result;
  }
}

class _Track {
  const _Track(
      this.start, this.pregap, this.sectors, this.size, this.mode, this.offset);
  final int start, pregap, sectors, size, mode, offset;
}

class _Cursor {
  _Cursor(this.bytes);
  final Uint8List bytes;
  int position = 0;
  void skip(int count) {
    if (count < 0 || position + count > bytes.length) {
      throw const FormatException('Truncated CDI descriptor');
    }
    position += count;
  }

  int word(int size) {
    final start = position;
    skip(size);
    var value = 0;
    for (var i = 0; i < size; i++) {
      value += bytes[start + i] * (1 << (8 * i));
    }
    return value;
  }
}

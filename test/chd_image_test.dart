import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cdrom_image/cdrom_image.dart';
import 'package:cdrom_image/format/chd/cd_ecc.dart';
import 'package:cdrom_image/memory.dart';
import 'package:test/test.dart';

import 'chd_fixture.dart';

const frameBytes = 2448;

/// an uncompressed CHD (version 5) of [tracks]: (metadata text, frames of
/// 2448 bytes). the frames of each track are padded to a multiple of 4.
Uint8List uncompressedChd(List<(String, List<Uint8List>)> tracks,
    {int framesPerHunk = 4}) {
  final hunkBytes = framesPerHunk * frameBytes;
  final frames = <Uint8List>[];
  for (final (_, data) in tracks) {
    frames.addAll(data);
    while (frames.length % 4 != 0) {
      frames.add(Uint8List(frameBytes));
    }
  }
  final hunks = (frames.length + framesPerHunk - 1) ~/ framesPerHunk;

  final out = BytesBuilder();
  void u32(int v) =>
      out.add([v >> 24, v >> 16, v >> 8, v].map((b) => b & 0xff).toList());
  void u64(int v) {
    u32(v >> 32);
    u32(v & 0xffffffff);
  }

  // the header, the map, the metadata, then the hunks
  const headerBytes = 124;
  final mapOffset = headerBytes;
  final metaOffset = mapOffset + hunks * 4;
  final meta = BytesBuilder();
  for (int i = 0; i < tracks.length; i++) {
    final text = Uint8List.fromList([...tracks[i].$1.codeUnits, 0]);
    final next =
        i + 1 < tracks.length ? metaOffset + meta.length + 16 + text.length : 0;
    meta.add('CHT2'.codeUnits);
    meta.add(
        [0, text.length >> 16, text.length >> 8 & 0xff, text.length & 0xff]);
    meta.add([
      for (int b = 7; b >= 0; b--) (next >> (b * 8)) & 0xff,
    ]);
    meta.add(text);
  }
  var dataOffset = metaOffset + meta.length;
  dataOffset = (dataOffset + hunkBytes - 1) ~/ hunkBytes * hunkBytes;

  out.add('MComprHD'.codeUnits);
  u32(headerBytes);
  u32(5);
  for (int i = 0; i < 4; i++) {
    u32(0); // uncompressed
  }
  u64(frames.length * frameBytes);
  u64(mapOffset);
  u64(metaOffset);
  u32(hunkBytes);
  u32(frameBytes);
  out.add(Uint8List(60)); // sha1s, no parent
  for (int h = 0; h < hunks; h++) {
    u32(dataOffset ~/ hunkBytes + h);
  }
  out.add(meta.toBytes());
  out.add(Uint8List(dataOffset - out.length));
  for (final f in frames) {
    out.add(f);
  }
  while (out.length < dataOffset + hunks * hunkBytes) {
    out.addByte(0);
  }
  return out.toBytes();
}

/// an uncompressed DVD CHD (version 5) of [sectors] of 2048 bytes, two
/// sectors in a hunk
Uint8List dvdChd(List<Uint8List> sectors) {
  const sectorBytes = 2048, hunkBytes = 2 * sectorBytes;
  final hunks = (sectors.length + 1) ~/ 2;
  final out = BytesBuilder();
  void u32(int v) =>
      out.add([v >> 24, v >> 16, v >> 8, v].map((b) => b & 0xff).toList());
  void u64(int v) {
    u32(v >> 32);
    u32(v & 0xffffffff);
  }

  const headerBytes = 124, mapOffset = headerBytes;
  final metaOffset = mapOffset + hunks * 4;
  const metaBytes = 16 + 1;
  final dataOffset =
      (metaOffset + metaBytes + hunkBytes - 1) ~/ hunkBytes * hunkBytes;
  out.add('MComprHD'.codeUnits);
  u32(headerBytes);
  u32(5);
  for (int i = 0; i < 4; i++) {
    u32(0); // uncompressed
  }
  u64(sectors.length * sectorBytes);
  u64(mapOffset);
  u64(metaOffset);
  u32(hunkBytes);
  u32(sectorBytes);
  out.add(Uint8List(60)); // sha1s, no parent
  for (int h = 0; h < hunks; h++) {
    u32(dataOffset ~/ hunkBytes + h);
  }
  out
    ..add('DVD '.codeUnits)
    ..add([0, 0, 0, 1])
    ..add(Uint8List(8)) // no next entry
    ..addByte(0)
    ..add(Uint8List(dataOffset - out.length - 0));
  for (final s in sectors) {
    out.add(s);
  }
  out.add(Uint8List(dataOffset + hunks * hunkBytes - out.length));
  return out.toBytes();
}

Uint8List frame(int fill, {int size = 2352}) =>
    Uint8List(frameBytes)..fillRange(0, size, fill);

Future<DiscImage> open(Uint8List chd) async {
  final file = MemoryDiscFile('disc.chd', chd);
  final (image, refs) = await DiscImage.parse(file);
  expect(refs, isEmpty);
  return image;
}

void main() {
  group('raw subchannels', () {

    for (final codec in ['cdzl', 'cdlz', 'cdfl']) {
    }
  });

  chdmanFixture();

  test('tracks, pregaps and the 4 frame padding', () async {
    final image = await open(uncompressedChd([
      (
        'TRACK:1 TYPE:MODE1_RAW SUBTYPE:NONE FRAMES:5 PREGAP:0 PGTYPE:MODE1 '
            'PGSUB:NONE POSTGAP:0',
        [for (int i = 0; i < 5; i++) frame(i + 1)]
      ),
      (
        // a pregap of 2 frames stored before the track
        'TRACK:2 TYPE:AUDIO SUBTYPE:NONE FRAMES:6 PREGAP:2 PGTYPE:VAUDIO '
            'PGSUB:NONE POSTGAP:0',
        [for (int i = 0; i < 6; i++) frame(0x10 + i)]
      ),
      (
        // a pregap of 3 frames not stored: silence
        'TRACK:3 TYPE:MODE1_RAW SUBTYPE:NONE FRAMES:2 PREGAP:3 PGTYPE:MODE1 '
            'PGSUB:NONE POSTGAP:0',
        [frame(0x20), frame(0x21)]
      ),
    ]));
    expect(
        [for (final t in image.toc.tracks) (t.number, t.isAudio, t.startLba)],
        [(1, false, 0), (2, true, 7), (3, false, 14)]);
    expect([for (final t in image.toc.tracks) t.sectors], [7, 7, 2]);
    expect(image.totalSectors, 16);

    final sectors = await image.readSectors(0, 16);
    expect([
      for (final s in sectors) s[100]
    ], [
      1,
      2,
      3,
      4,
      5,
      0x10,
      0x11,
      0x12,
      0x13,
      0x14,
      0x15,
      0,
      0,
      0,
      0x20,
      0x21
    ]);
  });

  for (final mode in [1, 2]) {
  }
}

void chdmanFixture() {
  // made by chdman 0.242 with its default codecs, and by chdman 0.289 with
  // -c cdzs,cdfl
  for (final (name, codecs) in [
    ('small.chd', 'cdlz, cdzl, cdfl'),
    ('small_zstd.chd', 'cdzs, cdfl'),
  ]) {
    test('a CHD made by chdman ($codecs) gives the sectors of the disc',
        () async {
      final file =
          MemoryDiscFile(name, File('test/fixtures/$name').readAsBytesSync());
      final (image, _) = await DiscImage.parse(file);
      expect([
        for (final t in image.toc.tracks)
          (t.number, t.isAudio, t.startLba, t.sectors)
      ], [
        (1, false, 0, dataSectors),
        (2, true, dataSectors, audioSectors)
      ]);
      final expected = fixtureSectors();
      final sectors = await image.readSectors(0, image.totalSectors);
      for (int lba = 0; lba < expected.length; lba++) {
        expect(sectors[lba], expected[lba], reason: 'lba $lba');
      }
    });

  }
}

import 'dart:typed_data';

import 'package:cdrom_image/cdrom_image.dart';
import 'package:cdrom_image/format/file_image.dart' show FileImage;
import 'package:cdrom_image/memory.dart';
import 'package:test/test.dart';

const size = DiscImage.sectorSize;

/// the image of [disc], the arguments of [DiscImage.parse]
Future<DiscImage> open((DiscFile, Iterable<DiscFile>) disc) async =>
    (await DiscImage.parse(disc.$1, files: disc.$2)).$1;

Future<DiscImage> insert(String main, Map<String, Uint8List> files) =>
    open(memoryDisc(main, {
      for (final e in files.entries) e.key: MemoryDiscFile(e.key, e.value)
    }));

Future<Uint8List> read(DiscImage image, int lba) async =>
    (await image.readSectors(lba, 1)).single;

/// each sector is filled with (file id + sector number) & 0xff
Uint8List makeBin(int sectors, {int id = 0}) {
  final data = Uint8List(sectors * size);
  for (int i = 0; i < sectors; i++) {
    data.fillRange(i * size, (i + 1) * size, (id + i) & 0xff);
  }
  return data;
}

/// 2048 bytes per sector, sector n is filled with n + 1
Uint8List cooked(int sectors) {
  final data = Uint8List(sectors * 2048);
  for (int i = 0; i < sectors; i++) {
    data.fillRange(i * 2048, (i + 1) * 2048, i + 1);
  }
  return data;
}

void main() {
  test('disc images are told by the extension', () {
    expect(DiscFileKind.of('a/Game.CUE'), DiscFileKind.image);
    expect(DiscFileKind.of('game.iso'), DiscFileKind.image);
    expect(DiscFileKind.of('game.bin'), DiscFileKind.maybeImage);
    expect(DiscFileKind.of('game.md'), DiscFileKind.notImage);
  });

  test('parse accepts walked files and resolves nested CUE paths in any order',
      () async {
    final directory = MemoryDirectory.of({
      'second/track.bin': makeBin(2, id: 42),
      'first/disc.cue': Uint8List.fromList(
          'FILE "TRACK.BIN" BINARY\n TRACK 01 MODE1/2352\n INDEX 01 00:00:00'
              .codeUnits),
      'second/disc.cue': Uint8List.fromList(
          'FILE "track.bin" BINARY\n TRACK 01 MODE1/2352\n INDEX 01 00:00:00'
              .codeUnits),
      'first/track.bin': makeBin(1, id: 7),
    });
    final files = directory.files.values.toList();
    final (first, firstFiles) = await DiscImage.parse(
        files.singleWhere((file) => file.path == 'first/disc.cue'),
        files: directory.files.values);
    final (second, secondFiles) = await DiscImage.parse(
        files.singleWhere((file) => file.path == 'second/disc.cue'),
        files: directory.files.values);
    expect((await first.readSectors(0, 1)).single[100], 7);
    expect((await second.readSectors(0, 1)).single[100], 42);
    expect(firstFiles.map((file) => file.path), ['first/track.bin']);
    expect(secondFiles.map((file) => file.path), ['second/track.bin']);
    expect(first.totalSectors, 1);
    expect(second.totalSectors, 2);
  });

  group('cooked images', () {
    test('.iso of 2048 bytes/sector is expanded to raw mode 1 sectors',
        () async {
      final image = await insert("a.iso", {"a.iso": cooked(4)});
      expect(image.totalSectors, 4);

      final s = await read(image, 2);
      expect(s.length, size);
      expect(s.sublist(0, 12), FileImage.sync);
      expect(s.sublist(12, 16), [0, 2, 2, 1]); // 00:02:02 mode 1
      expect(s.sublist(16, 16 + 2048).every((b) => b == 3), true);
    });

  });

  group('DiscImage', () {

    test('cue: multiple files', () async {
      const cue = '''
FILE "t1.bin" BINARY
  TRACK 01 MODE2/2352
    INDEX 01 00:00:00
FILE "t2.bin" BINARY
  TRACK 02 AUDIO
    INDEX 00 00:00:00
    INDEX 01 00:02:00
''';
      final image = await open(memoryDisc("a.cue", {
        "a.cue": MemoryDiscFile("a.cue", Uint8List.fromList(cue.codeUnits)),
        "t1.bin": MemoryDiscFile("t1.bin", makeBin(300)),
        "t2.bin": MemoryDiscFile("t2.bin", makeBin(400)),
      }));
      expect([for (final t in image.toc.tracks) t.startLba], [0, 450]);
      expect([for (final t in image.toc.tracks) t.sectors], [450, 250]);
      expect(image.totalSectors, 700);
      final seg = (image as FileImage).segments(450, 1).single;
      expect(seg.file!.path, "t2.bin");
      expect(seg.fileSector, 150);
    });
  });
}

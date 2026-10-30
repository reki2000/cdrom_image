import 'dart:typed_data';

import 'package:cdrom_image/cdrom_image.dart';
import 'package:cdrom_image/memory.dart';
import 'package:test/test.dart';

import 'cdi_fixture.dart';

Future<Uint8List> fixture(String name) async =>
    name == 'cdi_mode1.cdi' ? cdiMode1Fixture() : cdiSessionsFixture();
Future<DiscImage> parse(Uint8List bytes) async =>
    (await DiscImage.parse(MemoryDiscFile('authored.CDI', bytes))).$1;

Uint8List pattern(int seed, int sector, int size) => Uint8List.fromList(
    List.generate(size, (i) => (seed + sector * 17 + i * 3) & 255));

void main() {
  test('CDI classification and standalone parsing retain explicit session data',
      () async {
    expect(DiscFileKind.of('games/test.CDI'), DiscFileKind.image);
    final file = MemoryDiscFile('authored.cdi', await fixture('cdi_mode1.cdi'));
    final (image, references) = await DiscImage.parse(file);
    expect(references, isEmpty);
    expect(image.totalSectors, 3);
    expect(image.toc.tracks.single.startLba, 0);
    expect(image.toc.tracks.single.sectors, 3);
    expect(image.toc.tracks.single.isAudio, isFalse);
    final session = image.toc.sessions!.single;
    expect((session.number, session.firstTrack, session.startLba), (1, 1, 0));
    final sectors = await image.readSectors(0, 3);
    for (var i = 0; i < 3; i++) {
      expect(sectors[i].length, 2352);
      expect(sectors[i][15], 1);
      expect(sectors[i].sublist(16, 2064), pattern(7, i + 2, 2048));
      expect(sectors[i].sublist(2064), everyElement(0));
    }
  });

  test(
      'mixed sector sizes, optional headers and multiple sessions retain offsets',
      () async {
    final image = await parse(await fixture('cdi_sessions.cdi'));
    expect(image.totalSectors, 45002);
    expect(
        image.toc.tracks
            .map((t) => (t.number, t.isAudio, t.startLba, t.sectors)),
        [(1, true, 0, 5), (2, false, 5, 44995), (3, false, 45000, 2)]);
    expect(image.toc.sessions!.map((s) => (s.number, s.firstTrack, s.startLba)),
        [(1, 1, 0), (2, 3, 45000)]);
    final first = await image.readSectors(0, 6);
    for (var i = 0; i < 3; i++) {
      expect(first[i], pattern(11, i + 2, 2352));
    }
    expect(first[3], everyElement(0));
    expect(first[4].sublist(16, 2064), pattern(29, 0, 2048));
    expect(first[5].sublist(16, 2064), pattern(29, 1, 2048));
    final last = await image.readSectors(44997, 5);
    expect(last.first, everyElement(0));
    for (var i = 1; i < last.length; i++) {
      expect(last[i][15], 2);
      expect(last[i].sublist(16), pattern(47, i - 1, 2336));
    }
    first[0][0] = 0;
    expect((await image.readSectors(0, 1)).single, pattern(11, 2, 2352));
  });

  test(
      'read ranges include empty end reads and reject negative or excess ranges',
      () async {
    final image = await parse(await fixture('cdi_mode1.cdi'));
    expect(await image.readSectors(3, 0), isEmpty);
    expect(image.isReadable(-1), isFalse);
    expect(image.isReadable(2), isTrue);
    expect(image.isReadable(3), isFalse);
    for (final (lba, count) in [(-1, 1), (0, -1), (3, 1), (2, 2)]) {
      await expectLater(image.readSectors(lba, count), throwsRangeError);
    }
  });

  test(
      'short payload reads and storage errors propagate after a successful parse',
      () async {
    final file = _FailingFile(cdiMode1Fixture());
    final (image, _) = await DiscImage.parse(file);
    file.short = true;
    await expectLater(image.readSectors(0, 1), throwsFormatException);
    file.short = false;
    final failure = StateError('storage unavailable');
    file.failure = failure;
    await expectLater(image.readSectors(0, 1), throwsA(same(failure)));
  });

  test(
      'invalid footers, markers, extents and unsupported encodings never fall back to BIN',
      () async {
    final original = await fixture('cdi_mode1.cdi');
    final footer = original.length - 8;
    final descriptor = original.length -
        ByteData.sublistView(original).getUint32(footer + 4, Endian.little);
    Future<void> invalid(int offset, int value, {int size = 4}) async {
      final bytes = Uint8List.fromList(original);
      final view = ByteData.sublistView(bytes);
      if (size == 2) {
        view.setUint16(offset, value, Endian.little);
      } else {
        view.setUint32(offset, value, Endian.little);
      }
      await expectLater(parse(bytes), throwsA(isA<DiscParseException>()));
    }

    await invalid(footer, 0x80000005);
    await invalid(footer + 4, original.length + 1);
    await invalid(footer + 4, 8);
    await invalid(descriptor, 0, size: 2);
    await invalid(descriptor + 2, 0, size: 2);
    await invalid(descriptor + 8, 0);
    await invalid(descriptor + 4, 2);
    await invalid(descriptor + 4 + 48 + 12, 123);
    await invalid(descriptor + 4 + 60 + 12, 3, size: 2);
    await invalid(descriptor + 4 + 154 + 12, 123);
    // The generated filename adds twelve bytes to each canonical track offset.
    await invalid(descriptor + 4 + 66 + 12, 0);
    await invalid(descriptor + 4 + 96 + 12, 1000);
    await invalid(descriptor + 4 + 116 + 12, 3);
    await invalid(descriptor + 4 + 76 + 12, 2);
    await expectLater(parse(Uint8List(4)), throwsA(isA<DiscParseException>()));
  });
}

class _FailingFile extends MemoryDiscFile {
  _FailingFile(Uint8List bytes) : super('failure.cdi', bytes);
  bool short = false;
  Object? failure;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (failure != null) throw failure!;
    return super.read(offset, short ? length - 1 : length);
  }
}

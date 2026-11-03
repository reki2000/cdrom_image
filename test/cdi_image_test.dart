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

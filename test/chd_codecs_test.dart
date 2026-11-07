import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cdrom_image/format/chd/codecs.dart';
import 'package:test/test.dart';

void main() {
  test('a raw deflate stream is inflated', () {
    final random = Random(1);
    final data = Uint8List.fromList([
      for (int i = 0; i < 20000; i++)
        i % 7 == 0 ? random.nextInt(256) : i & 0x3f
    ]);
    final comp = Uint8List.fromList(ZLibEncoder(raw: true).convert(data));
    expect(inflate(comp, data.length), data);
  });

}

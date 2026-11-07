import 'dart:io';
import 'dart:typed_data';

import 'package:cdrom_image/format/chd/flac.dart';
import 'package:test/test.dart';

/// the frames of a .flac file: after "fLaC" and the metadata blocks
Uint8List frames(Uint8List flac) {
  var pos = 4;
  while (true) {
    final last = flac[pos] & 0x80 != 0;
    final length = flac[pos + 1] << 16 | flac[pos + 2] << 8 | flac[pos + 3];
    pos += 4 + length;
    if (last) return Uint8List.sublistView(flac, pos);
  }
}

void main() {
  // pcm: 11025 samples of 16-bit little-endian stereo. the .flac files are
  // made by the flac command with -0 (fixed predictors) and -8 (LPC), with
  // blocks of 2352 samples like CHD
  final pcm = File('test/fixtures/flac_pcm.raw').readAsBytesSync();
  final samples = pcm.length ~/ 4;

  for (final level in [0, 8]) {
    test('frames of flac -$level are decoded to big-endian samples', () {
      final flac = File('test/fixtures/flac_$level.flac').readAsBytesSync();
      final data = frames(flac);
      final (out, used) = FlacDecoder.decodeStereo16(data, samples);
      expect(used, data.length);
      // big-endian: the bytes of each sample are swapped from the pcm
      final expected = Uint8List(pcm.length);
      for (int i = 0; i < pcm.length; i += 2) {
        expected[i] = pcm[i + 1];
        expected[i + 1] = pcm[i];
      }
      expect(out, expected);
    });
  }

}

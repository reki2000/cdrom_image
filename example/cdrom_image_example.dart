import 'dart:io';
import 'dart:typed_data';

import 'package:cdrom_image/cdrom_image.dart';

class LocalDiscFile extends DiscFile {
  final File file;
  @override
  final String path;

  LocalDiscFile(this.file, this.path);

  @override
  Future<int> length() => file.length();

  @override
  Future<Uint8List> read(int offset, int length) async {
    final handle = await file.open(); // Separate handle for each read.
    try {
      await handle.setPosition(offset);
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }
}

Future<void> main() async {
  final cue = LocalDiscFile(File('example/images/disc.cue'), 'disc.cue');
  final bin = LocalDiscFile(File('example/images/track.bin'), 'track.bin');

  // Supply known references, or all candidate files.
  final (image, referenced) = await DiscImage.parse(cue, files: [bin]);
  stdout.writeln(referenced.map((file) => file.path)); // (track.bin)
  stdout.writeln(image.toc.tracks);

  final sectors = await image.readSectors(0, 1);
  stdout.writeln(sectors.first.length); // 2352
}

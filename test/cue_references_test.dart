import 'dart:typed_data';

import 'package:cdrom_image/cdrom_image.dart';
import 'package:cdrom_image/memory.dart';
import 'package:test/test.dart';

Uint8List text(String s) => Uint8List.fromList(s.codeUnits);

String cue(List<String> names) => [
      for (int i = 0; i < names.length; i++)
        'FILE "${names[i]}" BINARY\n  TRACK ${i + 1} MODE1/2352\n    INDEX 01 00:00:00'
    ].join("\n");

final bin = Uint8List(2352 * 4);

/// the paths of the files [path] of [files] refers to
Future<List<String>> referenced(
    Map<String, Uint8List> files, String path) async {
  final dir = MemoryDirectory.of(files);
  final (_, refs) =
      await DiscImage.parse(dir.files[path]!, files: dir.files.values);
  return [for (final f in refs) f.path];
}

Matcher missing(String name) => throwsA(isA<DiscParseException>()
    .having((e) => e.referencedPath, 'referencedPath', name));

class _BrokenFile extends DiscFile {
  @override
  String get path => 'broken.cue';
  @override
  Future<int> length() async => throw const FileSystemError();
  @override
  Future<Uint8List> read(int offset, int length) async =>
      throw const FileSystemError();
}

class FileSystemError implements Exception {
  const FileSystemError();
}

void main() {

  test('the files a cue refers to are returned', () async {
    expect(
        await referenced({
          "game/game.cue":
              text(cue(["game (Track 1).bin", "game (Track 2).bin"])),
          "game/game (Track 1).bin": bin,
          "game/game (Track 2).bin": bin,
          "single.bin": bin,
        }, "game/game.cue"),
        ["game/game (Track 1).bin", "game/game (Track 2).bin"]);
  });

}

// the image formats, told by the file name
import '../filesystem_api.dart';
import '../image_api.dart';
import 'cdi/cdi_image.dart';
import 'chd/chd_image.dart';
import 'cue/cue_image.dart';
import 'disc_source.dart';
import 'iso/iso_image.dart';

/// Parses [file], resolving the referenced tracks in [files].
Future<(DiscImage, List<DiscFile>)> parse(DiscFile file,
    {Iterable<DiscFile> files = const []}) async {
  try {
    if (file.path.toLowerCase().endsWith('.cdi')) {
      return (await CdiImage.open(file), <DiscFile>[]);
    }
    if (ChdImage.isChd(file.path)) {
      return (await ChdImage.open(file), <DiscFile>[]);
    }
    final source = DiscSource(files, file);
    final image =
        await (source.isCue ? CueImage.open(source) : openIso(source));
    return (image, List<DiscFile>.unmodifiable(source.referenced.values));
  } on FormatException catch (error) {
    throw DiscParseException(file.path, error.message, cause: error);
  }
}

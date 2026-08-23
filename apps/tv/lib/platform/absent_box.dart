import 'box.dart';

/// A machine that offers none of it.
///
/// What a desktop or a single-board computer gets until somebody writes its
/// half: every answer is empty or `false`, and the interface says nothing
/// about why. It does not need to — the screens already treat absence as
/// absence. No installed apps means no apps row; no volumes means no storage
/// tab; no display information means the screen section says the machine did
/// not say.
///
/// So a Raspberry Pi running this gets the home screen, the catalogue, the
/// player, television and search, and simply does not grow the parts that
/// belong to a set-top box. That is the whole point of putting the platform
/// behind one seam.
class AbsentBox implements Box {
  const AbsentBox();

  @override
  bool get present => false;

  @override
  Future<String?> installer() async => null;

  @override
  Future<List<InstalledApp>> apps() async => const [];

  @override
  Future<AppArt?> art(String package) async => null;

  @override
  Future<bool> launch(String package) async => false;

  @override
  Future<bool> settings() async => false;

  @override
  Future<List<StorageVolume>> storage() async => const [];

  @override
  Future<bool> wifi() async => false;

  @override
  Future<List<String>> abis() async => const [];

  @override
  Future<String> stagingDir() async => '';

  @override
  Future<bool> canInstall() async => false;

  @override
  Future<bool> requestInstall() async => false;

  @override
  Future<bool> install(String path) async => false;

  @override
  Future<void> clearStaging() async {}

  @override
  Future<bool> canReadFiles() async => false;

  @override
  Future<bool> requestReadFiles() async => false;

  @override
  Future<List<BoxRoot>> roots() async => const [];

  @override
  Future<List<BoxFile>> listDir(String path) async => const [];

  @override
  Future<bool> openFile(String path) async => false;

  @override
  Future<bool> store(String package) async => false;

  @override
  Future<bool> openWeb(String url, {String? agent}) async => false;

  @override
  Future<DisplayInfo?> display() async => null;

  @override
  Future<bool> preferMode(int modeId) async => false;

  @override
  Future<bool> holdMulticast() async => false;

  @override
  Future<bool> releaseMulticast() async => false;

  /// Never closes, and never says anything. A machine with no HOME button has
  /// nothing to report, and a stream that ended would look like a failure.
  @override
  Stream<BoxEvent> events() => const Stream.empty();
}

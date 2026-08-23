/// Reads an HLS master playlist into the qualities it offers.
///
/// Parsing only: fetching the playlist is the caller's job, so this is
/// testable without a network. Same shape as the other packages here.
library;

export 'src/master.dart';

/// The sections along the top, in the order they appear.
///
/// Named rather than indexed: the row was a list of strings and a `switch` on
/// position, and inserting one in the middle silently sent every tab after it
/// to the wrong screen. Storing which are *hidden* rather than which are shown
/// means a section added in a later version turns up for everybody.
enum NavTab {
  search('search', 'Пошук', '/search', optional: false),
  home('home', 'Головна', '/', optional: false),
  catalog('catalog', 'Каталог', '/catalog'),
  tv('tv', 'ТБ', '/tv'),
  playlists('playlists', 'Плейлисти', '/playlists'),
  fun('fun', 'Розваги', '/fun', needsBox: true),
  cameras('cameras', 'Камери', '/cameras', needsBox: true),
  apps('apps', 'Застосунки', '/apps', needsBox: true),
  storage('storage', 'Сховище', '/storage', needsBox: true);

  const NavTab(
    this.id,
    this.title,
    this.path, {
    this.optional = true,
    this.needsBox = false,
  });

  final String id;
  final String title;

  /// Where the section lives, which in a browser is also what the address bar
  /// shows. The id is what settings store and cannot change without losing
  /// everybody's choices; this is what a person can be handed.
  final String path;

  /// Whether the section is only there when the machine has a launcher half.
  ///
  /// Not a matter of taste like [optional] — these have nothing to show
  /// without one. Installed apps and drives are the box's; the cameras and the
  /// local-network scan need sockets a browser does not hand out, and cloud
  /// gaming opens somebody else's app. In a browser tab each of them is an
  /// empty screen with an explanation, which is worse than not being there.
  final bool needsBox;

  /// Whether it can be switched off.
  ///
  /// Home and search cannot: one is where BACK lands from everywhere, and the
  /// other is the only way to reach a title whose row was switched off. A box
  /// with neither would have no way out of itself.
  final bool optional;

  static NavTab? tryParse(String? id) {
    for (final tab in values) {
      if (tab.id == id) return tab;
    }
    return null;
  }
}

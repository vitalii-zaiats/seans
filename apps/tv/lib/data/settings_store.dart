import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../core/home_hero.dart';
import '../core/keypad.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// What the launcher looks like and when it steps aside.
@immutable
class Settings {
  const Settings({
    this.accentId = 'blurple',
    this.groundId = 'nocturne',
    this.idleMinutes = 8,
    this.focusGlow = true,
    this.uiScale = 1,
    this.hiddenRails = const {},
    this.hiddenTabs = const {},
    this.heroMode = HomeHero.slider,
    this.preferredModeId = 0,
    this.useDoh = false,
    this.pointer = false,
    this.typingMode = TypingMode.keyboard,
  });

  /// Id of the chosen accent, from `Nocturne.accents`.
  final String accentId;

  /// Id of the chosen ground, from `Nocturne.grounds`.
  final String groundId;

  /// Minutes of nothing before the idle screen takes over; `0` disables it.
  final int idleMinutes;

  /// Whether the focused tile's glow breathes. Off is the quieter setting for
  /// a television somebody sits close to.
  final bool focusGlow;

  /// Multiplies every measurement taken off the design.
  ///
  /// A television is watched from anywhere between one and five metres, and
  /// the same 1920-wide layout is either comfortable or unreadable depending
  /// which. `1` is the design as drawn.
  final double uiScale;

  /// Ids of the home rows the owner switched off.
  ///
  /// Hidden rather than shown, so a row added in a later version appears for
  /// everybody instead of staying invisible until somebody goes looking.
  final Set<String> hiddenRails;

  /// Ids of the top-row sections the owner switched off.
  ///
  /// Hidden rather than shown, for the same reason as [hiddenRails]: a section
  /// added in a later version should turn up rather than stay invisible.
  final Set<String> hiddenTabs;

  /// What sits at the top of the home screen.
  ///
  /// Worth its own setting rather than a rail: somebody who does not want
  /// somebody else's artwork filling the screen still wants the rows under it.
  final HomeHero heroMode;

  /// The display mode the owner asked for, or `0` to leave it to the system.
  ///
  /// Kept because the request lives on a window: it has to be made again every
  /// time the launcher starts, or the box goes back to whatever it chose.
  final int preferredModeId;

  /// Whether names are looked up over HTTPS rather than through the network's
  /// own resolver.
  ///
  /// **Off by default, and that is not caution — it breaks things.** Opening
  /// the socket to an address this app resolved goes through
  /// `HttpClient.connectionFactory`, and on that path ashdi answers `400`
  /// where an ordinary client gets `200`: the server hosts many sites on one
  /// address and no longer knows which one is wanted. Measured, not guessed.
  ///
  /// Kept because it is worth having where a resolver is the problem, and
  /// because the failure is loud rather than silent.
  final bool useDoh;

  /// Whether a pointer moves focus and clicks act.
  ///
  /// The default depends on where this is running, because the answer does. On
  /// a television only an air mouse produces a pointer, so the handlers would
  /// be dead weight on every tile and a stray event could pull focus out from
  /// under somebody's thumb. In a browser or on a desktop there is always a
  /// pointer — and defaulting to off there locks the interface out of its own
  /// window: nothing answers a click, and the arrows do nothing because the
  /// view never got focus to begin with.
  final bool pointer;

  /// How text gets typed where there is no keyboard to type it with.
  ///
  /// The grid by default, because it is the one that needs nothing explained:
  /// the letters are on the screen and the arrows walk to them. The number
  /// keys are faster for anybody who remembers a telephone and a puzzle for
  /// anybody who does not, which is the right way round for a setting.
  final TypingMode typingMode;

  /// Whether this machine has a pointer at all, and so what [pointer]
  /// defaults to before anybody chooses.
  ///
  /// `kIsWeb` first: `dart:io` compiles for the web as a stub that throws the
  /// moment it is touched, so `Platform` may not be read there.
  static bool get pointerByDefault => kIsWeb || !Platform.isAndroid;

  bool showsRail(String id) => !hiddenRails.contains(id);

  bool showsTab(String id) => !hiddenTabs.contains(id);

  bool get idleEnabled => idleMinutes > 0;

  Settings copyWith({
    String? accentId,
    String? groundId,
    int? idleMinutes,
    bool? focusGlow,
    double? uiScale,
    Set<String>? hiddenRails,
    Set<String>? hiddenTabs,
    HomeHero? heroMode,
    int? preferredModeId,
    bool? useDoh,
    bool? pointer,
    TypingMode? typingMode,
  }) => Settings(
    accentId: accentId ?? this.accentId,
    groundId: groundId ?? this.groundId,
    idleMinutes: idleMinutes ?? this.idleMinutes,
    focusGlow: focusGlow ?? this.focusGlow,
    uiScale: uiScale ?? this.uiScale,
    hiddenRails: hiddenRails ?? this.hiddenRails,
    hiddenTabs: hiddenTabs ?? this.hiddenTabs,
    heroMode: heroMode ?? this.heroMode,
    preferredModeId: preferredModeId ?? this.preferredModeId,
    useDoh: useDoh ?? this.useDoh,
    pointer: pointer ?? this.pointer,
    typingMode: typingMode ?? this.typingMode,
  );

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.accentId == accentId &&
      other.groundId == groundId &&
      other.idleMinutes == idleMinutes &&
      other.focusGlow == focusGlow &&
      other.uiScale == uiScale &&
      other.hiddenRails.length == hiddenRails.length &&
      other.hiddenRails.containsAll(hiddenRails) &&
      other.hiddenTabs.length == hiddenTabs.length &&
      other.hiddenTabs.containsAll(hiddenTabs) &&
      other.heroMode == heroMode &&
      other.preferredModeId == preferredModeId &&
      other.useDoh == useDoh &&
      other.pointer == pointer &&
      other.typingMode == typingMode;

  @override
  int get hashCode => Object.hash(
    accentId,
    groundId,
    idleMinutes,
    focusGlow,
    uiScale,
    Object.hashAllUnordered(hiddenRails),
    Object.hashAllUnordered(hiddenTabs),
    heroMode,
    preferredModeId,
    useDoh,
    pointer,
    typingMode,
  );
}

/// Holds the settings and tells the app when they change.
///
/// The change signal is [listenable] rather than the store itself: the store
/// is handed around by `RepositoryProvider`, which refuses a `Listenable`
/// outright — it cannot rebuild dependents, so being given one is almost
/// always a mistake. The whole app rebuilds from [listenable] at the root
/// instead, because the theme is built out of these values.
class SettingsStore {
  SettingsStore(this._prefs) : _notifier = ValueNotifier(_read(_prefs));

  static const _accent = 'settings.accent';
  static const _ground = 'settings.ground';
  static const _idle = 'settings.idleMinutes';
  static const _glow = 'settings.focusGlow';
  static const _scale = 'settings.uiScale';
  static const _hiddenRails = 'settings.hiddenRails';
  static const _hiddenTabs = 'settings.hiddenTabs';
  static const _hero = 'settings.heroMode';
  static const _mode = 'settings.displayMode';
  static const _doh = 'settings.useDoh';
  static const _pointer = 'settings.pointer';
  static const _typing = 'settings.typingMode';

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final ValueNotifier<Settings> _notifier;

  /// The current settings.
  Settings get value => _notifier.value;

  /// Fires whenever any of them changes.
  ValueListenable<Settings> get listenable => _notifier;

  void dispose() => _notifier.dispose();

  static Settings _read(SharedPreferences prefs) => Settings(
    accentId: prefs.getString(_accent) ?? 'blurple',
    groundId: prefs.getString(_ground) ?? 'nocturne',
    idleMinutes: prefs.getInt(_idle) ?? 8,
    focusGlow: prefs.getBool(_glow) ?? true,
    uiScale: prefs.getDouble(_scale) ?? 1,
    hiddenRails: (prefs.getStringList(_hiddenRails) ?? const []).toSet(),
    hiddenTabs: (prefs.getStringList(_hiddenTabs) ?? const []).toSet(),
    heroMode: HomeHero.fromId(prefs.getString(_hero)),
    preferredModeId: prefs.getInt(_mode) ?? 0,
    useDoh: prefs.getBool(_doh) ?? false,
    pointer: prefs.getBool(_pointer) ?? Settings.pointerByDefault,
    typingMode: TypingMode.fromId(prefs.getString(_typing)),
  );

  Future<void> setAccent(String id) async {
    _notifier.value = value.copyWith(accentId: id);
    await _prefs.setString(_accent, id);
  }

  Future<void> setGround(String id) async {
    _notifier.value = value.copyWith(groundId: id);
    await _prefs.setString(_ground, id);
  }

  Future<void> setIdleMinutes(int minutes) async {
    _notifier.value = value.copyWith(idleMinutes: minutes);
    await _prefs.setInt(_idle, minutes);
  }

  Future<void> setTypingMode(TypingMode mode) async {
    _notifier.value = value.copyWith(typingMode: mode);
    await _prefs.setString(_typing, mode.id);
  }

  Future<void> setFocusGlow(bool enabled) async {
    _notifier.value = value.copyWith(focusGlow: enabled);
    await _prefs.setBool(_glow, enabled);
  }

  /// Back to the palette and sizes the design was drawn in.
  Future<void> clear() async {
    _notifier.value = const Settings();
    await _prefs.remove(_accent);
    await _prefs.remove(_ground);
    await _prefs.remove(_idle);
    await _prefs.remove(_glow);
    await _prefs.remove(_scale);
    await _prefs.remove(_hiddenRails);
    await _prefs.remove(_hiddenTabs);
    await _prefs.remove(_hero);
    await _prefs.remove(_mode);
    await _prefs.remove(_doh);
    await _prefs.remove(_pointer);
    await _prefs.remove(_typing);
  }

  /// Shows or hides one home row, and says which it did.
  Future<bool> toggleRail(String id) async {
    final hidden = {...value.hiddenRails};
    final nowShown = hidden.remove(id);
    if (!nowShown) hidden.add(id);

    _notifier.value = value.copyWith(hiddenRails: hidden);
    await _prefs.setStringList(_hiddenRails, hidden.toList());
    return nowShown;
  }

  /// Shows or hides one top-row section, and says which it did.
  Future<bool> toggleTab(String id) async {
    final hidden = {...value.hiddenTabs};
    final nowShown = hidden.remove(id);
    if (!nowShown) hidden.add(id);

    _notifier.value = value.copyWith(hiddenTabs: hidden);
    await _prefs.setStringList(_hiddenTabs, hidden.toList());
    return nowShown;
  }

  /// Sets one section without having to know its current state — what a list
  /// of checkboxes needs, where a toggle would flip whatever happened to be
  /// there.
  Future<void> setTab(String id, {required bool shown}) async {
    if (value.showsTab(id) != shown) await toggleTab(id);
  }

  Future<void> setRail(String id, {required bool shown}) async {
    if (value.showsRail(id) != shown) await toggleRail(id);
  }

  Future<void> setHeroMode(HomeHero mode) async {
    _notifier.value = value.copyWith(heroMode: mode);
    await _prefs.setString(_hero, mode.id);
  }

  Future<void> setPreferredModeId(int id) async {
    _notifier.value = value.copyWith(preferredModeId: id);
    await _prefs.setInt(_mode, id);
  }

  Future<void> setUseDoh(bool value) async {
    _notifier.value = value
        ? this.value.copyWith(useDoh: true)
        : this.value.copyWith(useDoh: false);
    await _prefs.setBool(_doh, value);
  }

  Future<void> setPointer(bool enabled) async {
    _notifier.value = value.copyWith(pointer: enabled);
    await _prefs.setBool(_pointer, enabled);
  }

  Future<void> setUiScale(double scale) async {
    _notifier.value = value.copyWith(uiScale: scale);
    await _prefs.setDouble(_scale, scale);
  }
}

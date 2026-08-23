import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/remote/back.dart';
import '../../core/remote/focus_area.dart';
import '../../data/camera_store.dart';
import '../../data/iptv_store.dart';
import '../../data/library_store.dart';
import '../../data/onboarding_store.dart';
import '../../data/pinned_apps_store.dart';
import '../../data/playlist_store.dart';
import '../../data/steam_store.dart';
import '../../data/sweet_tv_store.dart';
import '../../data/settings_store.dart';
import '../../theme/nocturne.dart';
import '../../widgets/focusable.dart';

/// Wipes everything the launcher keeps on the box and starts setup over.
///
/// Its own screen rather than a chip that acts on the press: this cannot be
/// undone, and the list below is the only chance anybody gets to see what
/// exactly goes. Cancel takes the focus.
class ResetScreen extends StatelessWidget {
  const ResetScreen({super.key});

  static const _goes = [
    (
      Icons.play_circle_outline_rounded,
      'Історія перегляду',
      'Позиції в усьому, що ви дивились, і рейка «Продовжити дивитись».',
    ),
    (
      Icons.playlist_play_rounded,
      'Плейлисти й «Мій список»',
      'Усі створені списки разом із тим, що в них додано.',
    ),
    (
      Icons.palette_outlined,
      'Вигляд',
      'Колір, тло, масштаб інтерфейсу, заставка — усе повернеться до типового.',
    ),
    (
      Icons.restart_alt_rounded,
      'Відповіді з майстра',
      'Акаунт і підтримка проєкту, включно зі згодою ділитись інтернетом. '
          'Після скидання майстер запуститься спочатку.',
    ),
  ];

  Future<void> _wipe(BuildContext context) async {
    // The onboarding store goes last: the app is listening to it, and clearing
    // it is what swaps the screen for the wizard. Doing it first would tear the
    // tree down before the rest had been written.
    final library = context.read<LibraryStore>();
    final playlists = context.read<PlaylistStore>();
    final iptv = context.read<IptvStore>();
    final sweet = context.read<SweetTvStore>();
    final steam = context.read<SteamStore>();
    final cameras = context.read<CameraStore>();
    final pinnedApps = context.read<PinnedAppsStore>();
    final settings = context.read<SettingsStore>();
    final onboarding = context.read<OnboardingStore>();

    await library.clear();
    await playlists.clear();
    await iptv.clear();
    await sweet.clear();
    await steam.clear();
    await cameras.clear();
    await pinnedApps.clear();
    await settings.clear();
    await onboarding.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.px(80),
            context.px(48),
            context.px(80),
            context.px(40),
          ),
          // One area: the two buttons at the foot are the whole of what can
          // be pressed here, and `anchor` keeps focus on the screen while the
          // wall of copy above them is being read.
          child: FocusArea(
            landing: true,
            anchor: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Скинути лаунчер',
                  style: TextStyle(
                    fontSize: context.sp(38),
                    fontWeight: FontWeight.w500,
                    color: Nocturne.text,
                  ),
                ),
                SizedBox(height: context.px(10)),
                SizedBox(
                  width: context.px(1000),
                  child: Text(
                    'Усе, що лаунчер зберігає на цій приставці, буде стерто. '
                    'Скасувати це неможливо.',
                    style: TextStyle(
                      fontSize: context.sp(19),
                      height: 1.5,
                      color: Nocturne.neutral400,
                    ),
                  ),
                ),
                SizedBox(height: context.px(28)),

                Expanded(
                  child: ListView(
                    clipBehavior: Clip.none,
                    children: [
                      for (final (icon, title, body) in _goes)
                        Padding(
                          padding: EdgeInsets.only(bottom: context.px(18)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                icon,
                                size: context.px(24),
                                color: context.accent,
                              ),
                              SizedBox(width: context.px(18)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: context.sp(20),
                                        color: Nocturne.text,
                                      ),
                                    ),
                                    SizedBox(height: context.px(4)),
                                    Text(
                                      body,
                                      style: TextStyle(
                                        fontSize: context.sp(16),
                                        height: 1.45,
                                        color: Nocturne.neutral500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(top: context.px(6)),
                        child: Text(
                          'Сам застосунок і те, що встановлено на боксі, '
                          'лишаються на місці.',
                          style: TextStyle(
                            fontSize: context.sp(16),
                            color: Nocturne.neutral600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: context.px(12)),
                Row(
                  children: [
                    _Action(
                      label: 'Скасувати',
                      preferred: true,
                      // Not `Navigator.pop`: on the web this screen is a
                      // location rather than a pushed route, and there
                      // would be nothing on the stack to pop. One way out,
                      // and the ⌫ key takes the very same one.
                      onSelect: () => Back.requestFrom(context),
                    ),
                    SizedBox(width: context.px(14)),
                    _Action(
                      label: 'Стерти все і почати спочатку',
                      destructive: true,
                      onSelect: () => _wipe(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatefulWidget {
  const _Action({
    required this.label,
    required this.onSelect,
    this.preferred = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onSelect;
  final bool preferred;
  final bool destructive;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // The destructive one is outlined in the accent only once focused, so it
    // never reads as the obvious thing to press.
    final border = _focused
        ? context.accent
        : (widget.destructive ? Nocturne.neutral800 : Nocturne.neutral700);

    return Focusable(
      preferred: widget.preferred,
      scaleOnFocus: 1.03,
      onSelect: widget.onSelect,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(28),
          vertical: context.px(16),
        ),
        decoration: BoxDecoration(
          color: _focused ? context.accentTint : Colors.transparent,
          border: Border.all(color: border, width: context.px(1)),
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: context.sp(19),
            color: _focused
                ? context.accentText
                : (widget.destructive ? Nocturne.neutral400 : Nocturne.text),
          ),
        ),
      ),
    );
  }
}

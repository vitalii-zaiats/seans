import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/navigate.dart';
import '../../core/home_hero.dart';
import '../../core/home_rails.dart';
import '../../core/nav_tab.dart';
import '../../data/camera_store.dart';
import '../../data/iptv_store.dart';
import '../../data/onboarding_store.dart';
import '../../data/settings_store.dart';
import '../../data/startup.dart';
import '../../data/steam_store.dart';
import '../../data/sweet_tv_store.dart';
import '../../platform/box_for_platform.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../../widgets/focusable.dart';
import 'screen_section.dart';

/// The groups down the left of the settings screen.
enum SettingsGroup {
  look('Вигляд'),
  home('Головна'),
  sections('Розділи'),
  tv('Телебачення'),
  cameras('Камери', needsBox: true),
  fun('Розваги', needsBox: true),
  idle('Заставка'),
  // `wm size` and `wm density` — a panel's real resolution against the one the
  // launcher draws in. A browser window has neither.
  screen('Екран', needsBox: true),
  // Choosing a resolver is something a process with sockets can do. In a
  // browser every request goes through `fetch`, which resolves names itself
  // and offers no say in it.
  network('Мережа', needsBox: true),
  // Selling idle bandwidth needs a machine that idles and a socket to sell it
  // through. A tab has neither.
  support('Підтримка', needsBox: true),
  system('Система');

  const SettingsGroup(this.title, {this.needsBox = false});

  final String title;

  /// Whether the group is only there on a machine with a launcher half.
  ///
  /// Same rule as `NavTab.needsBox`, and for the same reason: a group whose
  /// every control is a no-op is worse than a missing one — it reads as a
  /// setting that does not work rather than one that does not apply.
  final bool needsBox;

  static List<SettingsGroup> get forThisMachine => [
    for (final group in values)
      if (!group.needsBox || platformBox.present) group,
  ];
}

/// How the launcher looks, what it shows, and when it steps aside.
///
/// Groups on the left, their settings on the right. It was one long scroll,
/// and every option added made finding any of them worse — on a remote, a list
/// you have to walk past is a list you have to walk back through.
///
/// Every choice applies on the press: the theme is built from these values, so
/// the screen you are standing on repaints as you walk the row. Nothing to
/// save, nothing to confirm.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  var _group = SettingsGroup.look;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SettingsStore>();

    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<Settings>(
          valueListenable: store.listenable,
          builder: (context, settings, _) => Padding(
            padding: EdgeInsets.fromLTRB(
              context.px(80),
              context.px(48),
              context.px(80),
              context.px(40),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Налаштування',
                  style: TextStyle(
                    fontSize: context.sp(38),
                    fontWeight: FontWeight.w500,
                    color: Nocturne.text,
                  ),
                ),
                SizedBox(height: context.px(28)),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: context.px(340),
                        child: ListView(
                          clipBehavior: Clip.none,
                          children: [
                            for (final group in SettingsGroup.forThisMachine)
                              _GroupRow(
                                group: group,
                                selected: group == _group,
                                autofocus: group == SettingsGroup.look,
                                onSelect: () => setState(() => _group = group),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: context.px(60)),
                      Expanded(
                        child: _Pane(group: _group, settings: settings),
                      ),
                    ],
                  ),
                ),
                Text(
                  '↑↓ група  ·  → до налаштувань  ·  ⌫ назад',
                  style: TextStyle(
                    fontSize: context.sp(14),
                    color: Nocturne.neutral700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One name in the left column.
///
/// Selected on focus, not on OK: walking the list should show what is in each
/// group, and pressing a button to look would make it a two-step job every
/// time.
class _GroupRow extends StatefulWidget {
  const _GroupRow({
    required this.group,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
  });

  final SettingsGroup group;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;

    return Focusable(
      autofocus: widget.autofocus,
      scaleOnFocus: 1,
      glow: false,
      onSelect: widget.onSelect,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) widget.onSelect();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: context.px(6)),
        padding: EdgeInsets.symmetric(
          horizontal: context.px(20),
          vertical: context.px(14),
        ),
        decoration: BoxDecoration(
          color: _focused ? context.accentTint : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: active ? context.accent : Colors.transparent,
              width: context.px(3),
            ),
          ),
        ),
        child: Text(
          widget.group.title,
          style: TextStyle(
            fontSize: context.sp(20),
            color: active ? Nocturne.text : Nocturne.neutral500,
          ),
        ),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.group, required this.settings});

  final SettingsGroup group;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      clipBehavior: Clip.none,
      children: switch (group) {
        SettingsGroup.look => [_Look(settings: settings)],
        SettingsGroup.home => [_Home(settings: settings)],
        SettingsGroup.sections => [_Sections(settings: settings)],
        SettingsGroup.tv => [const _Tv()],
        SettingsGroup.cameras => [const _Cameras()],
        SettingsGroup.fun => [const _Fun()],
        SettingsGroup.idle => [_Idle(settings: settings)],
        SettingsGroup.screen => [
          const _Section(
            label: 'ЕКРАН',
            note:
                'Те саме, що показують `wm size` і `wm density`, плюс те, у '
                'чому насправді малює лаунчер',
            child: ScreenSection(),
          ),
        ],
        SettingsGroup.network => [_Network(settings: settings)],
        SettingsGroup.support => [const _SupportSection()],
        SettingsGroup.system => [const _System()],
      },
    );
  }
}

class _Look extends StatelessWidget {
  const _Look({required this.settings});

  static const _scaleChoices = <(double, String)>[
    (0.85, 'Дрібний'),
    (1, 'Звичайний'),
    (1.15, 'Крупний'),
    (1.3, 'Дуже крупний'),
  ];

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SettingsStore>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          label: 'АКЦЕНТ',
          note: 'Колір рамки фокуса, підписів і позначок',
          child: TvChipRow(
            itemCount: Nocturne.accents.length,
            builder: (context, index) {
              final option = Nocturne.accents[index];
              return TvChip(
                label: option.label,
                swatch: option.color,
                selected: option.id == settings.accentId,
                onSelect: () => store.setAccent(option.id),
              );
            },
          ),
        ),
        _Section(
          label: 'ТЛО',
          note: 'Ґрунт, на якому лежить увесь інтерфейс',
          child: TvChipRow(
            itemCount: Nocturne.grounds.length,
            builder: (context, index) {
              final option = Nocturne.grounds[index];
              return TvChip(
                label: option.label,
                swatch: option.color,
                selected: option.id == settings.groundId,
                onSelect: () => store.setGround(option.id),
              );
            },
          ),
        ),
        _Section(
          label: 'МАСШТАБ',
          note:
              'Розмір усього інтерфейсу — під розмір панелі й відстань до '
              'дивана',
          child: TvChipRow(
            itemCount: _scaleChoices.length,
            builder: (context, index) {
              final (scale, label) = _scaleChoices[index];
              return TvChip(
                label: label,
                hint: '${(scale * 100).round()}%',
                selected: scale == settings.uiScale,
                onSelect: () => store.setUiScale(scale),
              );
            },
          ),
        ),
        // Only where a pointer is optional. In a browser there is always one,
        // and switching it off would take the click handlers down with it —
        // a setting whose "off" is "the interface stops responding".
        if (platformBox.present)
          _Section(
            label: 'КУРСОР',
            note:
                'Для пультів з гіроскопом — «повітряної миші». На звичайному '
                'пульті вмикати нема сенсу: курсора там немає, а обробники '
                'наведення висять на кожній плитці',
            child: TvChipRow(
              itemCount: 2,
              builder: (context, index) {
                final on = index == 0;
                return TvChip(
                  label: on ? 'Увімкнено' : 'Вимкнено',
                  selected: on == settings.pointer,
                  onSelect: () => store.setPointer(on),
                );
              },
            ),
          ),
        _Section(
          label: 'СЯЙВО ФОКУСА',
          note: 'Пульсація навколо виділеної плитки',
          child: TvChipRow(
            itemCount: 2,
            builder: (context, index) {
              final on = index == 0;
              return TvChip(
                label: on ? 'Увімкнено' : 'Вимкнено',
                selected: on == settings.focusGlow,
                onSelect: () => store.setFocusGlow(on),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SettingsStore>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          label: 'ВЕРХ ЕКРАНА',
          note:
              'Банер — це чужі обкладинки на третину екрана щоразу, коли '
              'вмикається приставка. Годинник нічого не рекламує і нічого не '
              'завантажує',
          child: TvChipRow(
            itemCount: HomeHero.values.length,
            builder: (context, index) {
              final mode = HomeHero.values[index];
              return TvChip(
                label: mode.title,
                hint: mode.note,
                selected: mode == settings.heroMode,
                onSelect: () => store.setHeroMode(mode),
              );
            },
          ),
        ),
        _Section(
          label: 'РЯДКИ НА ГОЛОВНІЙ',
          note: 'Вимкнений рядок не завантажується взагалі',
          child: TvChipRow(
            itemCount: HomeRailId.values.length,
            builder: (context, index) {
              final rail = HomeRailId.values[index];
              return TvChip(
                label: rail.title,
                selected: settings.showsRail(rail.id),
                onSelect: () => store.toggleRail(rail.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SettingsStore>();
    final optional = [
      for (final tab in NavTab.values)
        // A switch for a section this machine does not have is a switch that
        // does nothing, which reads as a bug rather than as a platform. The
        // same goes for one the shop will not let this build carry.
        if (tab.optional &&
            (!tab.needsBox || platformBox.present) &&
            context.read<Startup>().allows(tab.id))
          tab,
    ];

    return _Section(
      label: 'РОЗДІЛИ ВГОРІ',
      note:
          'Вимкнений розділ зникає з рядка. «Головна» і «Пошук» лишаються '
          'завжди — інакше з приставки не буде виходу',
      child: TvChipRow(
        itemCount: optional.length,
        builder: (context, index) {
          final tab = optional[index];
          return TvChip(
            label: tab.title,
            selected: settings.showsTab(tab.id),
            onSelect: () => store.toggleTab(tab.id),
          );
        },
      ),
    );
  }
}

/// Where the channels come from.
///
/// Stateful because both stores behind it are plain preferences with no change
/// signal — nothing else in the app needs to hear about them, and giving them
/// listeners for one screen would be more machinery than the settings are
/// worth.
class _Tv extends StatefulWidget {
  const _Tv();

  @override
  State<_Tv> createState() => _TvState();
}

class _TvState extends State<_Tv> {
  late bool _sweet = context.read<SweetTvStore>().enabled;
  late bool _lists = context.read<IptvStore>().usesDefaults;

  @override
  Widget build(BuildContext context) {
    final sweet = context.read<SweetTvStore>();
    final iptv = context.read<IptvStore>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          label: 'SWEET.TV',
          note: 'Близько 140 безкоштовних каналів із програмою передач',
          child: TvChipRow(
            itemCount: 2,
            builder: (context, index) {
              final on = index == 0;
              return TvChip(
                label: on ? 'Увімкнено' : 'Вимкнено',
                selected: on == _sweet,
                onSelect: () async {
                  await sweet.setEnabled(on);
                  if (mounted) setState(() => _sweet = on);
                },
              );
            },
          ),
        ),
        _Section(
          label: 'ПУБЛІЧНІ M3U-СПИСКИ',
          note:
              'Вбудовані списки з GitHub. Дають більше каналів, але помітна '
              'їх частина мертва або недоступна з України. Свої списки, додані '
              'вручну, лишаються в будь-якому разі',
          child: TvChipRow(
            itemCount: 2,
            builder: (context, index) {
              final on = index == 0;
              return TvChip(
                label: on ? 'Завантажувати' : 'Не завантажувати',
                selected: on == _lists,
                onSelect: () async {
                  await iptv.setUsesDefaults(on);
                  if (mounted) setState(() => _lists = on);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Cameras, and the only way in before there are any.
///
/// The Камери tab appears once a camera exists, so the first one has to be
/// added from somewhere that is always there.
class _Cameras extends StatelessWidget {
  const _Cameras();

  @override
  Widget build(BuildContext context) {
    final store = context.read<CameraStore>();

    return ValueListenableBuilder<List<Camera>>(
      valueListenable: store.listenable,
      builder: (context, cameras, _) => _Section(
        label: 'КАМЕРИ',
        note: cameras.isEmpty
            ? 'Адресу RTSP видно в налаштуваннях самої камери. Розділ «Камери» '
                  'зʼявиться вгорі, щойно буде хоч одна'
            : '${cameras.length} у списку. Прибрати можна на самому розділі',
        child: TvChipRow(
          itemCount: cameras.length + 1,
          builder: (context, index) {
            if (index == cameras.length) {
              // Adding one opens a box-only screen, so the button comes back
              // with that feature — from `Parts`, where a browser build never
              // compiles it. The list itself is worth showing either way: the
              // cameras a box already knows about are still its settings.
              return TvChip(
                label: 'Додати камеру',
                enabled: false,
                onSelect: () {},
              );
            }
            final camera = cameras[index];
            return TvChip(
              label: camera.name,
              hint: camera.isRtsp ? null : 'не RTSP',
              enabled: false,
              onSelect: () {},
            );
          },
        ),
      ),
    );
  }
}

class _Fun extends StatefulWidget {
  const _Fun();

  @override
  State<_Fun> createState() => _FunState();
}

class _FunState extends State<_Fun> {
  late bool _scan = context.read<SteamStore>().enabled;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SteamStore>();

    return _Section(
      label: 'ПРИСТРОЇ В МЕРЕЖІ',
      note:
          'Пошук машин зі Steam — одна широкомовна датаграма по локальній '
          'мережі, назовні нічого не йде',
      child: TvChipRow(
        itemCount: 2,
        builder: (context, index) {
          final on = index == 0;
          return TvChip(
            label: on ? 'Шукати' : 'Не шукати',
            selected: on == _scan,
            onSelect: () async {
              await store.setEnabled(on);
              if (mounted) setState(() => _scan = on);
            },
          );
        },
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.settings});

  static const _choices = <(int, String)>[
    (0, 'Вимкнено'),
    (5, '5 хвилин'),
    (8, '8 хвилин'),
    (15, '15 хвилин'),
    (30, '30 хвилин'),
  ];

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SettingsStore>();

    return _Section(
      label: 'ЗАСТАВКА',
      note: 'Скільки чекати, перш ніж лишити на екрані годинник',
      child: TvChipRow(
        itemCount: _choices.length,
        builder: (context, index) {
          final (minutes, label) = _choices[index];
          return TvChip(
            label: label,
            selected: minutes == settings.idleMinutes,
            onSelect: () => store.setIdleMinutes(minutes),
          );
        },
      ),
    );
  }
}

class _System extends StatelessWidget {
  const _System();

  @override
  Widget build(BuildContext context) {
    // Built as a list rather than a `switch` on the index: one of these only
    // exists on a box, and a fixed `itemCount` with positional cases turns
    // "hide the second chip" into renumbering the other three.
    final chips = <Widget Function()>[
      // First, because it is the one somebody comes looking for: who this
      // machine is signed in as, and how to change that.
      () => TvChip(
        label: 'Акаунт',
        onSelect: () => openRoute(context, '/settings/account'),
      ),
      // Hands over to Android's own settings. There is nothing behind it in a
      // browser — a chip that does nothing is worse than one that is not there.
      if (platformBox.present)
        () =>
            TvChip(label: 'Налаштування боксу', onSelect: platformBox.settings),
      // Re-runs the wizard and nothing more — history, lists and colours
      // stay. The next chip is the one that erases.
      () => TvChip(
        label: 'Пройти майстер заново',
        onSelect: () => context.read<OnboardingStore>().reset(),
      ),
      () => TvChip(
        label: platformBox.present ? 'Скинути лаунчер' : 'Скинути застосунок',
        onSelect: () => openRoute(context, '/settings/reset'),
      ),
    ];

    return _Section(
      label: 'СИСТЕМА',
      note: platformBox.present
          ? 'Входи, мережа й памʼять належать боксу, не лаунчеру'
          : 'Акаунт і те, що зберігається в цьому браузері',
      child: TvChipRow(
        itemCount: chips.length,
        builder: (context, index) => chips[index](),
      ),
    );
  }
}

/// How names are looked up.
class _Network extends StatelessWidget {
  const _Network({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SettingsStore>();

    return _Section(
      label: 'DNS ЧЕРЕЗ HTTPS',
      note:
          'Імена запитуються в Cloudflare і Google напряму по IP, а не в '
          'резолвера мережі. Сертифікат при цьому перевіряється так само — '
          'змінюється лише те, хто відповідає «де воно», а не кому вірити. '
          'Якщо не спрацює, запит іде звичайним шляхом',
      child: TvChipRow(
        itemCount: 2,
        builder: (context, index) {
          final on = index == 0;
          return TvChip(
            label: on ? 'Увімкнено' : 'Вимкнено',
            hint: on ? null : 'резолвер мережі',
            selected: on == settings.useDoh,
            onSelect: () => store.setUseDoh(on),
          );
        },
      ),
    );
  }
}

/// What was agreed to during setup, and the way back out of it.
///
/// The consent screen promises this switch exists, so it has to — an agreement
/// somebody cannot withdraw without hunting for it is not much of one.
class _SupportSection extends StatefulWidget {
  const _SupportSection();

  @override
  State<_SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<_SupportSection> {
  late OnboardingState _answers = context.read<OnboardingStore>().read();

  Future<void> _stopSharing() async {
    final store = context.read<OnboardingStore>();
    await store.save(
      _answers.copyWith(support: SupportChoice.none, bandwidthConsent: false),
    );
    if (mounted) setState(() => _answers = store.read());
  }

  @override
  Widget build(BuildContext context) {
    final sharing = _answers.isSharingBandwidth;

    return _Section(
      label: 'ПІДТРИМКА',
      note: sharing
          ? 'Ви ділитесь інтернетом, коли приставка простоює'
          : 'Ділення інтернетом вимкнено',
      child: TvChipRow(
        itemCount: 1,
        builder: (context, index) => sharing
            ? TvChip(label: 'Припинити ділитись', onSelect: _stopSharing)
            : TvChip(
                label: 'Увімкнути можна в майстрі налаштування',
                enabled: false,
                onSelect: () {},
              ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.note,
    required this.child,
  });

  final String label;
  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.px(34)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvChipRowLabel(text: label),
          SizedBox(height: context.px(6)),
          Text(
            note,
            style: TextStyle(
              fontSize: context.sp(15),
              height: 1.4,
              color: Nocturne.neutral600,
            ),
          ),
          SizedBox(height: context.px(12)),
          child,
        ],
      ),
    );
  }
}

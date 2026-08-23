import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/network_probe.dart';
import '../../data/onboarding_store.dart';
import '../../platform/box_for_platform.dart';
import '../../platform/install_offer.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../../widgets/focusable.dart';

import 'package:super_movies_api/super_movies_api.dart' hide AccountMode;

import '../../data/startup.dart';
import '../pairing/pairing_cubit.dart';
import '../pairing/pairing_state.dart';
import 'onboarding_cubit.dart';
import 'widgets/onboarding_scaffold.dart';

/// First run: five questions, none of which can be answered wrongly.
///
/// Finishing writes `completed` to the store, and the app is listening to it —
/// there is no callback to fire, and nothing to keep in sync.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingCubit, OnboardingViewState>(
      builder: (context, state) => PopScope(
        // BACK steps the wizard back rather than popping the route: there is
        // one route under all eleven screens, and handing the press to the
        // system would close the app from the middle of setting it up.
        //
        // Except on the first screen, where there is nothing to unwind and the
        // press means what it always means — the way out of an app is not
        // something a wizard should be allowed to take away.
        canPop: !state.canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.read<OnboardingCubit>().back();
        },
        child: switch (state.step) {
          OnboardingStep.welcome => const _Welcome(),
          OnboardingStep.content => _Content(state: state),
          OnboardingStep.tv => const _Tv(),
          OnboardingStep.tvSources => _TvSources(state: state),
          OnboardingStep.fun => const _Fun(),
          OnboardingStep.account => const _Account(),
          OnboardingStep.pairing => BlocProvider(
            create: (context) => PairingCubit(
              context.read<SuperMoviesApi>(),
              context.read<Startup>(),
            )..start(),
            child: const _Pairing(),
          ),
          OnboardingStep.support => const _Support(),
          OnboardingStep.bandwidthConsent => const _BandwidthConsent(),
          // The connection check asks where this box is seen from and how
          // fast it is. In a browser that is a question about somebody
          // else's machine, and there is something worth asking instead.
          OnboardingStep.network =>
            kIsWeb ? const _InstallApp() : _Network(state: state),
          OnboardingStep.done => _Done(state: state),
        },
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Вітаємо',
      // The launcher copy is a promise about a set-top box: that this replaces
      // the home screen and leaves the other apps alone. In a browser tab
      // there is no home screen to replace and no other apps to reassure
      // anybody about, so it would be a sentence about somebody else's device.
      subtitle: platformBox.present
          ? 'Цей лаунчер замінює головний екран приставки: фільми й серіали '
                'відкриваються прямо звідси, а решта застосунків нікуди не '
                'дівається.\n\nНалаштування займе хвилину.'
          : 'Фільми, серіали і прямий ефір — в одному місці.'
                '\n\nНалаштування займе хвилину.',
      hint: 'OK продовжити',
      child: Align(
        alignment: Alignment.topLeft,
        child: _Action(
          label: 'Почати',
          autofocus: true,
          onSelect: context.read<OnboardingCubit>().start,
        ),
      ),
    );
  }
}

/// Which catalogue sections this box carries.
///
/// Asked before anything else because it is the one question whose answer
/// somebody already knows — and a section switched off here is a request the
/// home screen never makes, not a row hidden after the fact.
class _Content extends StatelessWidget {
  const _Content({required this.state});

  final OnboardingViewState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();
    final sections = OnboardingViewState.catalogueSections;

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.content),
      totalSteps: cubit.stepCount,
      title: 'Що дивитесь',
      subtitle:
          'Зніміть те, що вам не потрібно — ці рядки не з\'являться на '
          'головній, і лаунчер не питатиме про них каталог. Це завжди можна '
          'змінити в налаштуваннях.',
      hint: 'OK перемкнути  ·  «Далі» щоб продовжити',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TvChipRow(
            itemCount: sections.length,
            builder: (context, index) {
              final rail = sections[index];
              return TvChip(
                label: rail.title,
                selected: state.sections.contains(rail.id),
                autofocus: index == 0,
                onSelect: () => cubit.toggleSection(rail.id),
              );
            },
          ),
          SizedBox(height: context.px(30)),
          _Action(
            label: 'Далі',
            primary: true,
            onSelect: cubit.confirmSections,
          ),
        ],
      ),
    );
  }
}

/// Whether live television belongs on this box at all.
class _Tv extends StatelessWidget {
  const _Tv();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.tv),
      totalSteps: cubit.stepCount,
      title: 'Телебачення',
      subtitle:
          'Прямий ефір: безкоштовні канали з програмою передач, і публічні '
          'списки, якщо схочете. Не потрібно — вкладки ТБ просто не буде.',
      hint: 'OK вибрати',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Action(
            label: 'Так, потрібне',
            primary: true,
            autofocus: true,
            onSelect: () => cubit.chooseTv(wanted: true),
          ),
          SizedBox(width: context.px(16)),
          _Action(
            label: 'Не потрібне',
            onSelect: () => cubit.chooseTv(wanted: false),
          ),
        ],
      ),
    );
  }
}

/// Where the channels come from.
class _TvSources extends StatelessWidget {
  const _TvSources({required this.state});

  final OnboardingViewState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();
    const sources = <(String, String)>[
      (OnboardingViewState.sweetSource, 'SWEET.TV — безкоштовні'),
      (OnboardingViewState.playlistSource, 'Публічні M3U-списки'),
    ];

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.tv),
      totalSteps: cubit.stepCount,
      title: 'Джерела каналів',
      subtitle:
          'SWEET.TV дає близько 140 каналів із програмою передач. Публічні '
          'списки дають більше, але помітна їх частина мертва або недоступна '
          'з України. Свій список можна додати пізніше.',
      hint: 'OK перемкнути  ·  «Далі» щоб продовжити',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TvChipRow(
            itemCount: sources.length,
            builder: (context, index) {
              final (id, label) = sources[index];
              return TvChip(
                label: label,
                selected: state.tvSources.contains(id),
                autofocus: index == 0,
                onSelect: () => cubit.toggleTvSource(id),
              );
            },
          ),
          SizedBox(height: context.px(30)),
          _Action(
            label: 'Далі',
            primary: true,
            onSelect: cubit.confirmTvSources,
          ),
        ],
      ),
    );
  }
}

/// Whether the games section belongs here.
class _Fun extends StatelessWidget {
  const _Fun();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.fun),
      totalSteps: cubit.stepCount,
      title: 'Розваги',
      subtitle:
          'Хмарний геймінг — Xbox, GeForce NOW — і машини зі Steam у вашій '
          'мережі. Для хмарних сервісів потрібні акаунт, підписка й геймпад; '
          'для Steam — увімкнений комп\'ютер поруч.',
      hint: 'OK вибрати',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Action(
            label: 'Так, цікавить',
            primary: true,
            autofocus: true,
            onSelect: () => cubit.chooseFun(wanted: true),
          ),
          SizedBox(width: context.px(16)),
          _Action(
            label: 'Не цікавить',
            onSelect: () => cubit.chooseFun(wanted: false),
          ),
        ],
      ),
    );
  }
}

class _Account extends StatelessWidget {
  const _Account();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();
    // Answering costs two requests on the anonymous path, and which screen
    // comes next depends on what they answer — so the question waits here with
    // something to look at rather than moving on and guessing.
    final settling = context.select<OnboardingCubit, bool>(
      (one) => one.state.settling,
    );

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.account),
      totalSteps: cubit.stepCount,
      title: 'Акаунт',
      subtitle:
          'Потрібен лише для того, щоб «Продовжити дивитись» і список '
          'збереглися поза цією приставкою, і щоб керувати нею з телефона. '
          'Дивитись можна й без нього.',
      hint: settling ? 'Хвилинку…' : '↑↓ вибір  ·  OK підтвердити',
      child: ListView(
        clipBehavior: Clip.none,
        children: [
          ChoiceTile(
            autofocus: true,
            icon: Icons.tv_rounded,
            title: 'Продовжити анонімно',
            description:
                'Нічого не залишає цю приставку. Історія перегляду й список '
                'живуть тільки тут.',
            onSelect: settling
                ? () {}
                : () => cubit.chooseAccount(AccountMode.anonymous),
          ),
          ChoiceTile(
            icon: Icons.schedule_rounded,
            title: 'Продовжити як гість',
            description:
                'Те саме, але з локальним ідентифікатором — акаунт можна '
                'привʼязати пізніше, не втративши те, що вже переглянуто.',
            onSelect: settling
                ? () {}
                : () => cubit.chooseAccount(AccountMode.guest),
          ),
          ChoiceTile(
            icon: Icons.qr_code_2_rounded,
            title: 'Створити акаунт зараз',
            description:
                'Покажемо QR-код — відскануєте телефоном і завершите там.',
            onSelect: settling
                ? () {}
                : () => cubit.chooseAccount(AccountMode.linked),
          ),
        ],
      ),
    );
  }
}

/// The pairing screen.
///
/// There is no pairing service yet, so rather than draw a QR code that leads
/// nowhere this says so and offers the way on. The moment a session URL
/// exists, [_PairingCode] draws it and the rest of the screen is unchanged.
class _Pairing extends StatelessWidget {
  const _Pairing();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();
    final pairs = context.read<PairingCubit>();
    final pairing = context.watch<PairingCubit>().state;

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.account),
      totalSteps: cubit.stepCount,
      title: pairing.isLinked ? 'Готово' : 'Привʼязати телефон',
      subtitle: switch (pairing.status) {
        PairingStatus.linked =>
          'Ця приставка тепер входить у ваш акаунт. Те, що ви тут дивитесь, '
              'буде на будь-якому іншому екрані.',
        PairingStatus.expired =>
          'Код застарів — вони живуть кілька хвилин, щоб той, що лишився на '
              'екрані, перестав щось означати сам собою.',
        PairingStatus.failed =>
          pairing.error ?? 'Не вдалося попросити код. Спробуйте ще раз.',
        _ =>
          'Відскануйте код телефоном і завершіть створення акаунта там. '
              'Пароль на пульті нікому не потрібен.',
      },
      hint: pairing.isLinked ? 'OK далі' : 'OK продовжити як гість',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pairing.isWaiting && pairing.link != null) ...[
            _PairingCode(
              url: pairing.link!.verifyUrl(context.read<Uri>()).toString(),
            ),
            SizedBox(width: context.px(48)),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: switch (pairing.status) {
                // Nothing on screen yet is worth saying so: a blank half of a
                // setup screen reads as something that failed quietly.
                PairingStatus.asking => const _Asking(),
                PairingStatus.waiting => _Waiting(code: pairing.link!.code),
                PairingStatus.linked => _Action(
                  label: 'Далі',
                  autofocus: true,
                  onSelect: cubit.finishPairing,
                ),
                _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Action(
                      label: 'Показати новий код',
                      autofocus: true,
                      onSelect: pairs.start,
                    ),
                    SizedBox(height: context.px(12)),
                    _Action(
                      label: 'Продовжити як гість',
                      onSelect: cubit.skipPairing,
                    ),
                  ],
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// While the server is being asked for a code.
class _Asking extends StatelessWidget {
  const _Asking();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: context.px(20),
          height: context.px(20),
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: context.px(14)),
        Text(
          'Просимо код…',
          style: TextStyle(
            fontSize: context.sp(20),
            color: Nocturne.neutral400,
          ),
        ),
      ],
    );
  }
}

/// The code, spelled out beside the QR, and the way past it.
///
/// Both, because a camera is not always the answer: a phone with a cracked lens
/// or somebody standing too far back still has a keyboard, and the code is
/// short precisely so it can be typed.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Код',
          style: TextStyle(
            fontSize: context.sp(14),
            letterSpacing: 1.2,
            color: Nocturne.neutral700,
          ),
        ),
        SizedBox(height: context.px(6)),
        Text(
          code,
          style: TextStyle(
            fontSize: context.sp(56),
            fontWeight: FontWeight.w500,
            letterSpacing: context.px(10),
            color: Nocturne.text,
            // Every glyph the same width, so the code does not shift about as
            // somebody reads it across a room.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(height: context.px(20)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: context.px(16),
              height: context.px(16),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: context.px(12)),
            Text(
              'Чекаємо на телефон',
              style: TextStyle(
                fontSize: context.sp(18),
                color: Nocturne.neutral400,
              ),
            ),
          ],
        ),
        SizedBox(height: context.px(28)),
        _Action(
          label: 'Продовжити як гість',
          autofocus: true,
          onSelect: cubit.skipPairing,
        ),
      ],
    );
  }
}

class _PairingCode extends StatelessWidget {
  const _PairingCode({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.px(16)),
      decoration: BoxDecoration(
        // A QR code needs a light quiet zone to scan reliably; this is the one
        // place in the app that is not dark.
        color: Nocturne.neutral100,
        borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
      ),
      child: QrImageView(
        data: url,
        size: context.px(280),
        backgroundColor: Nocturne.neutral100,
      ),
    );
  }
}

class _Support extends StatelessWidget {
  const _Support();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.support),
      totalSteps: cubit.stepCount,
      title: 'Підтримати проєкт',
      subtitle:
          'Необовʼязково, і на роботу лаунчера це ніяк не впливає — усе '
          'працює однаково за будь-якої відповіді.',
      hint: '↑↓ вибір  ·  OK підтвердити',
      child: ListView(
        clipBehavior: Clip.none,
        children: [
          ChoiceTile(
            autofocus: true,
            icon: Icons.close_rounded,
            title: 'Не зараз',
            description:
                'Перейти далі. Запитаємо ще раз хіба що в '
                'налаштуваннях, коли самі зайдете.',
            onSelect: () => cubit.chooseSupport(SupportChoice.none),
          ),
          ChoiceTile(
            icon: Icons.favorite_outline_rounded,
            title: 'Разовий донат',
            description:
                'Одноразовий внесок. Нічого не підписується й нічого '
                'не списується повторно.',
            onSelect: () => cubit.chooseSupport(SupportChoice.donation),
          ),
          ChoiceTile(
            icon: Icons.share_rounded,
            title: 'Ділитись інтернетом',
            description:
                'Частина вашого каналу використовується, коли приставка '
                'простоює.',
            note:
                'Це означає, що чужий трафік виходитиме з вашої IP-адреси. '
                'Перш ніж вмикати, покажемо окремий екран із подробицями.',
            onSelect: () => cubit.chooseSupport(SupportChoice.bandwidth),
          ),
        ],
      ),
    );
  }
}

/// The consent screen for sharing the connection.
///
/// Deliberately its own step with its own question. Agreeing to route other
/// people's traffic through somebody's home line is not the sort of thing that
/// should ever be collected by highlighting a row in a list.
class _BandwidthConsent extends StatelessWidget {
  const _BandwidthConsent();

  static const _points = [
    (
      Icons.public_rounded,
      'Чужий трафік іде з вашої IP-адреси',
      'Запити інших людей виходитимуть в інтернет так, ніби їх зробили ви. '
          'За те, що саме вони роблять, ви не відповідаєте, але зовні це '
          'виглядає як ваше підключення.',
    ),
    (
      Icons.data_usage_rounded,
      'Витрачається ваш трафік',
      'Якщо у провайдера є ліміт або оплата за обсяг — це ваші гроші. '
          'На безлімітному тарифі помітите хіба що навантаження на роутер.',
    ),
    (
      Icons.schedule_rounded,
      'Тільки коли приставка простоює',
      'Під час перегляду канал не ділиться — швидкість відео важливіша.',
    ),
    (
      Icons.settings_backup_restore_rounded,
      'Вимикається будь-коли',
      'Один перемикач у налаштуваннях, без пояснень і без наслідків.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();

    return OnboardingScaffold(
      title: 'Перш ніж вмикати',
      subtitle: 'Прочитайте, будь ласка, до кінця — і скажіть, чи згодні.',
      hint: '↑↓ вибір  ·  OK підтвердити',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              clipBehavior: Clip.none,
              children: [
                for (final (icon, title, body) in _points)
                  Padding(
                    padding: EdgeInsets.only(bottom: context.px(18)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: context.px(24), color: context.accent),
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
              ],
            ),
          ),
          SizedBox(height: context.px(12)),
          Row(
            children: [
              _Action(
                label: 'Ні, дякую',
                autofocus: true,
                onSelect: () => cubit.answerBandwidthConsent(agreed: false),
              ),
              SizedBox(width: context.px(14)),
              _Action(
                label: 'Погоджуюсь ділитись',
                primary: true,
                onSelect: () => cubit.answerBandwidthConsent(agreed: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Network extends StatelessWidget {
  const _Network({required this.state});

  final OnboardingViewState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();
    final report = state.report;

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.network),
      totalSteps: cubit.stepCount,
      title: 'Підключення',
      subtitle: 'Перевіряємо, звідки видно приставку і чи вистачає швидкості.',
      hint: 'OK продовжити',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: state.probing || report == null
                ? Row(
                    children: [
                      SizedBox(
                        width: context.px(24),
                        height: context.px(24),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.accent,
                        ),
                      ),
                      SizedBox(width: context.px(16)),
                      Text(
                        'Вимірюємо…',
                        style: TextStyle(
                          fontSize: context.sp(18),
                          color: Nocturne.neutral500,
                        ),
                      ),
                    ],
                  )
                : _Report(report: report),
          ),
          Row(
            children: [
              // Offline is the one state where moving on is not the obvious
              // next step, so the Wi-Fi picker takes the focus instead.
              if (report != null && report.isOffline) ...[
                _Action(
                  label: 'Підключити Wi-Fi',
                  primary: true,
                  autofocus: true,
                  onSelect: platformBox.wifi,
                ),
                SizedBox(width: context.px(14)),
                _Action(label: 'Перевірити ще раз', onSelect: cubit.runProbe),
                SizedBox(width: context.px(14)),
                _Action(label: 'Пропустити', onSelect: cubit.showDone),
              ] else ...[
                _Action(
                  label: 'Далі',
                  primary: true,
                  autofocus: true,
                  onSelect: cubit.showDone,
                ),
                SizedBox(width: context.px(14)),
                _Action(label: 'Перевірити ще раз', onSelect: cubit.runProbe),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.report});

  final NetworkReport report;

  @override
  Widget build(BuildContext context) {
    final speed = report.megabitsPerSecond;

    return ListView(
      clipBehavior: Clip.none,
      children: [
        _Fact(label: 'IP-адреса', value: report.ip ?? 'невідомо'),
        _Fact(label: 'Провайдер', value: report.isp ?? 'невідомо'),
        _Fact(
          label: 'Країна',
          value: report.locationUnknown
              ? 'не вдалося визначити'
              : '${report.countryName} (${report.countryCode})',
          good: report.isInUkraine,
          bad: !report.isInUkraine && !report.locationUnknown,
        ),
        _Fact(
          label: 'Каталог',
          value: report.catalogueReachable ? 'відповідає' : 'недоступний',
          good: report.catalogueReachable,
          bad: !report.catalogueReachable,
        ),
        _Fact(
          label: 'Швидкість',
          value: speed == null
              ? 'не вдалося виміряти'
              : '${speed.toStringAsFixed(1)} Мбіт/с',
          good: report.isFastEnough,
          bad: speed != null && !report.isFastEnough,
        ),
        SizedBox(height: context.px(18)),
        if (!report.isInUkraine && !report.locationUnknown)
          _Notice(
            icon: Icons.travel_explore_rounded,
            title: 'Схоже, приставка не в Україні',
            body:
                'Каталог ліцензований для України, тож частина тайтлів може '
                'не відкритись. Допоможе проксі або VPN з українською '
                'IP-адресою.',
          ),
        if (speed != null && !report.isFastEnough)
          _Notice(
            icon: Icons.speed_rounded,
            title: 'Швидкості може не вистачити',
            body:
                'Для 1080p комфортно від 8 Мбіт/с. Нижче цього відео '
                'вмикатиметься довше і може падати в якості.',
          ),
        if (report.isOffline)
          _Notice(
            icon: Icons.wifi_off_rounded,
            title: 'Приставка не в мережі',
            body:
                'Жоден сервер не відповів — схоже, підключення немає взагалі. '
                'Кнопка нижче відкриє системний перелік Wi-Fi поверх цього '
                'екрана. Якщо бокс під кабелем, перевірте, чи він увімкнений.',
          )
        else if (!report.catalogueReachable)
          _Notice(
            icon: Icons.cloud_off_rounded,
            title: 'Каталог не відповідає',
            body:
                'Мережа є, але каталог мовчить. Найчастіше це блокування з '
                'боку провайдера — тоді допоможе проксі.',
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.good = false,
    this.bad = false,
  });

  final String label;
  final String value;
  final bool good;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.px(12)),
      child: Row(
        children: [
          SizedBox(
            width: context.px(220),
            child: Text(
              label,
              style: TextStyle(
                fontSize: context.sp(17),
                color: Nocturne.neutral600,
              ),
            ),
          ),
          if (good || bad) ...[
            Icon(
              good ? Icons.check_rounded : Icons.warning_amber_rounded,
              size: context.px(20),
              color: good ? context.accent : Nocturne.neutral400,
            ),
            SizedBox(width: context.px(10)),
          ],
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: context.sp(19), color: Nocturne.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: context.px(12)),
      padding: EdgeInsets.all(context.px(20)),
      decoration: BoxDecoration(
        color: context.accentTint,
        borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: context.px(24), color: context.accent),
          SizedBox(width: context.px(16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: context.sp(19),
                    color: Nocturne.text,
                  ),
                ),
                SizedBox(height: context.px(4)),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: context.sp(16),
                    height: 1.45,
                    color: Nocturne.neutral400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The last question in a browser: keep this as an app?
///
/// Everything that makes it possible is already shipped — Flutter registers
/// `flutter_service_worker.js` from `web/flutter_bootstrap.js`, and
/// `web/manifest.json` names the app and asks for a standalone window. What was
/// missing was anywhere to say yes: the browser's own offer hides in a menu
/// most people never open, and on a television-shaped interface it is invisible.
///
/// The offer is the browser's to make and it often will not: Chromium decides
/// on its own terms, Firefox and Safari never fire the event, and a copy that
/// is already installed does not either. So this screen has to read as complete
/// with the button missing — which is why the button is the extra, and moving
/// on is always there.
class _InstallApp extends StatelessWidget {
  const _InstallApp();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();

    return OnboardingScaffold(
      step: cubit.numberOf(OnboardingStep.network),
      totalSteps: cubit.stepCount,
      title: 'Застосунок',
      subtitle:
          'Можна лишити «Сеанс» окремим застосунком — він відкриється у своєму '
          'вікні, без адресного рядка, і буде під рукою поруч з іншими.',
      hint: 'OK продовжити',
      child: ValueListenableBuilder<bool>(
        valueListenable: installPrompt.available,
        builder: (context, offered, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                offered
                    ? 'Займе секунду. Видалити можна як звичайний застосунок.'
                    : 'Цей браузер не пропонує встановлення — або застосунок '
                          'уже встановлено. Нічого робити не треба, усе працює '
                          'і у вкладці.',
                style: TextStyle(
                  fontSize: context.sp(18),
                  color: Nocturne.neutral500,
                ),
              ),
            ),
            Row(
              children: [
                if (offered) ...[
                  _Action(
                    label: 'Встановити',
                    primary: true,
                    autofocus: true,
                    // Not awaited into a state change: whatever the person
                    // answers, the wizard is done asking. Accepting swaps the
                    // window under us, and declining should not strand anybody
                    // on a screen whose only button has just gone.
                    onSelect: () => unawaited(installPrompt.show()),
                  ),
                  SizedBox(width: context.px(14)),
                  _Action(label: 'Не треба', onSelect: cubit.showDone),
                ] else
                  _Action(
                    label: 'Далі',
                    primary: true,
                    autofocus: true,
                    onSelect: cubit.showDone,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.state});

  final OnboardingViewState state;

  @override
  Widget build(BuildContext context) {
    // No summary of what was just answered. It read as a receipt for a form,
    // and half of it was not even asked in a browser — where support never
    // comes up — so the last thing on screen would have reported a decision
    // nobody made.
    return OnboardingScaffold(
      title: 'Готово',
      subtitle: 'Дякуємо — і приємного перегляду.',
      hint: 'OK відкрити головну',
      child: Align(
        alignment: Alignment.topLeft,
        child: _Action(
          label: 'Почати дивитись',
          primary: true,
          autofocus: true,
          onSelect: context.read<OnboardingCubit>().finish,
        ),
      ),
    );
  }
}

/// An outlined action — the design never fills a button.
class _Action extends StatefulWidget {
  const _Action({
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final border = widget.primary || _focused
        ? context.accent
        : Nocturne.neutral700;

    return Focusable(
      autofocus: widget.autofocus,
      scaleOnFocus: 1.03,
      onSelect: widget.onSelect,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(30),
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
            color: _focused ? context.accentText : Nocturne.text,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../data/startup.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../pairing/pairing_cubit.dart';
import '../pairing/pairing_state.dart';

/// Who this box is, and the two ways that can change.
///
/// Three states, and the screen says which one plainly rather than making
/// somebody work it out from what is missing:
///
///     anonymous  nothing left this box, and nothing will until asked
///     guest      an account with no name on it — everything watched is kept
///                and can still be claimed
///     linked     an email, and the same history on any other screen
///
/// Both ways forward are here. A phone can sign this box in, which is the
/// pleasant one; and the box can be forgotten, which deletes the account rather
/// than merely stopping using it — an account somebody asked us to forget is
/// not one to keep a copy of.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          PairingCubit(context.read<SuperMoviesApi>(), context.read<Startup>()),
      child: const _Account(),
    );
  }
}

class _Account extends StatelessWidget {
  const _Account();

  @override
  Widget build(BuildContext context) {
    final startup = context.watch<Startup>();
    final pairing = context.watch<PairingCubit>().state;
    final account = pairing.account ?? startup.account;

    return Scaffold(
      backgroundColor: context.ground,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.px(48),
            context.px(36),
            context.px(48),
            context.px(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Акаунт',
                style: TextStyle(
                  fontSize: context.sp(40),
                  fontWeight: FontWeight.w500,
                  color: Nocturne.text,
                ),
              ),
              SizedBox(height: context.px(8)),
              Text(
                _explain(account, reached: startup.reached),
                style: TextStyle(
                  fontSize: context.sp(19),
                  height: 1.5,
                  color: Nocturne.neutral400,
                ),
              ),
              SizedBox(height: context.px(32)),
              Expanded(
                child: pairing.status == PairingStatus.idle
                    ? _Standing(account: account)
                    : _Pairing(pairing: pairing),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One sentence that says where this box stands, in its own terms.
  static String _explain(Account? account, {required bool reached}) {
    if (!reached) {
      return 'Немає звʼязку з сервером, тож про акаунт зараз сказати нічого. '
          'Дивитись це не заважає.';
    }
    if (account == null) {
      return 'Ця приставка нічого про себе не розповідає. Історія перегляду '
          'й список живуть тільки тут і нікуди не йдуть.';
    }
    if (account.isGuest) {
      return 'Гість. Те, що переглянуто, зберігається — але поки що лише за '
          'цією приставкою. Привʼяжіть телефон, і воно буде на будь-якому '
          'іншому екрані.';
    }
    return 'Приставка входить у ваш акаунт. Те, що ви тут дивитесь, є на '
        'будь-якому іншому екрані, де ви ввійшли.';
  }
}

/// What the box is, and what can be done about it.
class _Standing extends StatelessWidget {
  const _Standing({required this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final pairs = context.read<PairingCubit>();
    final startup = context.read<Startup>();
    final claimed = account != null && !account!.isGuest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (account != null) ...[
          _Field(label: 'ІМʼЯ', value: account!.displayName),
          SizedBox(height: context.px(18)),
          _Field(label: 'ПОШТА', value: account!.email ?? 'ще не привʼязана'),
          SizedBox(height: context.px(36)),
        ],
        TvChipRow(
          itemCount: claimed ? 1 : 2,
          builder: (context, index) {
            if (!claimed && index == 0) {
              return TvChip(label: 'Привʼязати телефон', onSelect: pairs.start);
            }
            return TvChip(
              label: account == null ? 'Стати гостем' : 'Забути цю приставку',
              hint: account == null
                  ? null
                  : 'акаунт буде видалено разом із сесіями',
              onSelect: () => account == null
                  ? startup.announce(remembered: true)
                  : startup.forget(),
            );
          },
        ),
      ],
    );
  }
}

/// The same dance the first-run wizard shows, on a screen somebody chose to
/// open rather than one they were walked through.
class _Pairing extends StatelessWidget {
  const _Pairing({required this.pairing});

  final PairingState pairing;

  @override
  Widget build(BuildContext context) {
    final pairs = context.read<PairingCubit>();

    return switch (pairing.status) {
      PairingStatus.asking => Row(
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
      ),
      PairingStatus.waiting => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Code(url: pairing.link!.verifyUrl(context.read<Uri>()).toString()),
          SizedBox(width: context.px(48)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(label: 'КОД', value: pairing.link!.code, big: true),
                SizedBox(height: context.px(24)),
                Text(
                  'Відскануйте телефоном і завершіть там. Пароль на пульті '
                  'нікому не потрібен.',
                  style: TextStyle(
                    fontSize: context.sp(18),
                    height: 1.5,
                    color: Nocturne.neutral400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      PairingStatus.linked => Text(
        'Готово — приставка тепер ${pairing.account?.email ?? "у вашому акаунті"}.',
        style: TextStyle(fontSize: context.sp(22), color: Nocturne.text),
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pairing.status == PairingStatus.expired
                ? 'Код застарів. Вони живуть кілька хвилин, щоб той, що '
                      'лишився на екрані, перестав щось означати сам собою.'
                : pairing.error ?? 'Не вдалося попросити код.',
            style: TextStyle(
              fontSize: context.sp(19),
              height: 1.5,
              color: Nocturne.neutral400,
            ),
          ),
          SizedBox(height: context.px(24)),
          TvChipRow(
            itemCount: 1,
            builder: (context, index) =>
                TvChip(label: 'Показати новий код', onSelect: pairs.start),
          ),
        ],
      ),
    };
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.big = false});

  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: context.sp(14),
            letterSpacing: 1.2,
            color: Nocturne.neutral700,
          ),
        ),
        SizedBox(height: context.px(6)),
        Text(
          value,
          style: TextStyle(
            fontSize: context.sp(big ? 52 : 24),
            fontWeight: big ? FontWeight.w500 : FontWeight.w400,
            letterSpacing: big ? context.px(10) : null,
            color: Nocturne.text,
            // Every glyph the same width, so a code does not shift about as
            // somebody reads it across a room.
            fontFeatures: big ? const [FontFeature.tabularFigures()] : null,
          ),
        ),
      ],
    );
  }
}

class _Code extends StatelessWidget {
  const _Code({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.px(16)),
      decoration: BoxDecoration(
        // A QR code needs a light quiet zone to scan reliably; this is one of
        // the two places in the app that is not dark.
        color: Nocturne.neutral100,
        borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
      ),
      child: QrImageView(
        data: url,
        size: context.px(260),
        backgroundColor: Nocturne.neutral100,
      ),
    );
  }
}

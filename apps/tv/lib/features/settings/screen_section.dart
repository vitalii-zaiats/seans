import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/settings_store.dart';
import '../../platform/box.dart';
import '../../platform/box_for_platform.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';

/// What the panel is running at, and what the launcher is drawing into.
///
/// The two are not the same number, and when they differ the picture is being
/// upscaled by something between them — which looks exactly like a blurry
/// launcher and has nothing on screen to explain it. `adb shell wm size` says
/// the same thing from a terminal; this says it from the sofa.
class ScreenSection extends StatefulWidget {
  const ScreenSection({super.key});

  @override
  State<ScreenSection> createState() => _ScreenSectionState();
}

class _ScreenSectionState extends State<ScreenSection> {
  final _box = platformBox;

  late Future<DisplayInfo?> _info = _box.display();

  /// Asks for a mode, remembers it, and re-reads what actually happened.
  ///
  /// The re-read is the point: the system is free to refuse, and a screen that
  /// showed the request rather than the result would be lying.
  Future<void> _prefer(int modeId) async {
    await context.read<SettingsStore>().setPreferredModeId(modeId);
    await _box.preferMode(modeId);

    // The switch takes a moment, and it takes the panel with it — the picture
    // goes black and comes back.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _info = _box.display());
  }

  /// What the mode list means, said plainly.
  ///
  /// This is the evidence for the question everybody asks when a box outputs
  /// 720p: is the box too weak, or is something between it and the panel?
  /// Outputting a resolution costs nothing — rendering at it does — so a panel
  /// offering nothing better is almost always the cable, the port, or
  /// something in the middle.
  static String _verdict(DisplayInfo info) {
    if (info.modes.isEmpty) return 'Приставка не перелічила режими.';

    final biggest = info.modes
        .map((mode) => mode.width)
        .reduce((a, b) => a > b ? a : b);

    if (biggest <= info.modeWidth) {
      return 'Нічого більшого за поточний режим не пропонується. Це не про '
          'потужність боксу — віддавати роздільність нічого не коштує. '
          'Зазвичай так буває, коли кабель не тягне, коли на телевізорі для '
          'цього входу вимкнено розширений режим HDMI (HDMI UHD Color, Deep '
          'Colour, Enhanced), або коли між ними стоїть світч чи ресивер.';
    }

    return 'Панель приймає більший режим, ніж працює зараз — можна попросити '
        'його нижче.';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DisplayInfo?>(
      future: _info,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        final info = snapshot.data;
        if (info == null) {
          return Text(
            'Приставка не повідомила про екран',
            style: TextStyle(
              fontSize: context.sp(17),
              color: Nocturne.neutral500,
            ),
          );
        }

        // What Flutter itself is laying out in. Read from the view rather than
        // from Android: this is the number every `context.px` is scaled
        // against, so it is the one that explains how big things look.
        final view = View.of(context);
        final logical = view.physicalSize / view.devicePixelRatio;
        final settings = context.watch<SettingsStore>().value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(
              label: 'РЕЖИМ ПАНЕЛІ',
              value: '${info.modeWidth} × ${info.modeHeight}',
              note:
                  '${info.refreshRate.toStringAsFixed(0)} Гц · те, що бокс '
                  'віддає по HDMI',
            ),
            _Row(
              label: 'ПОВЕРХНЯ ЗАСТОСУНКУ',
              value: '${info.surfaceWidth} × ${info.surfaceHeight}',
              note: info.isUpscaled
                  ? 'менша за режим — картинка розтягується, тому й мило'
                  : 'збігається з режимом',
              warn: info.isUpscaled,
            ),
            _Row(
              label: 'ЛОГІЧНІ ПІКСЕЛІ',
              value: '${logical.width.round()} × ${logical.height.round()}',
              note:
                  'масштаб ${view.devicePixelRatio.toStringAsFixed(2)}× · '
                  'у цьому інтерфейс і рахує розміри',
            ),
            _Row(
              label: 'ЩІЛЬНІСТЬ',
              value: '${info.densityDpi} dpi',
              note: 'wm density',
            ),
            SizedBox(height: context.px(8)),
            Text(
              'РЕЖИМИ, ЯКІ ПРИЙМАЄ ПАНЕЛЬ',
              style: TextStyle(
                fontSize: context.sp(12),
                letterSpacing: context.px(2),
                color: Nocturne.neutral700,
              ),
            ),
            SizedBox(height: context.px(6)),
            SizedBox(
              width: context.px(1100),
              child: Text(
                _verdict(info),
                style: TextStyle(
                  fontSize: context.sp(15),
                  height: 1.4,
                  color: info.bestUnused == null
                      ? context.accentSoft
                      : Nocturne.neutral600,
                ),
              ),
            ),
            SizedBox(height: context.px(12)),
            TvChipRow(
              itemCount: info.modes.length + 1,
              builder: (context, index) {
                if (index == 0) {
                  return TvChip(
                    label: 'Як вирішить бокс',
                    selected: settings.preferredModeId == 0,
                    onSelect: () => _prefer(0),
                  );
                }
                final mode = info.modes[index - 1];
                return TvChip(
                  label: mode.label,
                  hint: mode.active ? 'зараз' : null,
                  selected: settings.preferredModeId == mode.id,
                  onSelect: () => _prefer(mode.id),
                );
              },
            ),
            SizedBox(height: context.px(16)),
            SizedBox(
              width: context.px(1100),
              child: Text(
                'Це прохання, а не команда: система може його не виконати. '
                'Тримається, поки лаунчер на екрані, і запитується знову при '
                'кожному запуску.',
                style: TextStyle(
                  fontSize: context.sp(15),
                  height: 1.4,
                  color: Nocturne.neutral700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.note,
    this.warn = false,
  });

  final String label;
  final String value;
  final String note;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.px(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: context.sp(12),
              letterSpacing: context.px(2),
              color: Nocturne.neutral700,
            ),
          ),
          SizedBox(height: context.px(4)),
          Text(
            value,
            style: TextStyle(
              fontSize: context.sp(26),
              color: warn ? context.accentSoft : Nocturne.text,
            ),
          ),
          SizedBox(height: context.px(2)),
          Text(
            note,
            style: TextStyle(
              fontSize: context.sp(15),
              color: warn ? context.accentSoft : Nocturne.neutral600,
            ),
          ),
        ],
      ),
    );
  }
}

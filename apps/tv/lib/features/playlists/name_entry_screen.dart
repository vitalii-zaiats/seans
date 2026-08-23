import 'package:flutter/material.dart';

import '../../core/remote/back.dart';
import '../../core/remote/focus_area.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../../widgets/hardware_typing.dart';
import '../../widgets/dpad_keyboard.dart' show KeyboardLayout;
import '../../widgets/typing_pad.dart';

/// Types a name with the remote, does the one thing it was opened for, and
/// leaves.
///
/// Same keyboard the search screen uses — a television has one way to enter
/// text, and inventing a second one would only be a second thing to learn.
///
/// **A route like every other screen, rather than a `Navigator.push` returning
/// a value.** Pushed straight onto the navigator it had no address: the router
/// still believed the section underneath was what was showing, so the shell
/// drew the row of tabs over it — and that row was a reachable area sitting
/// above a screen that was really deeper. The typed name comes back through
/// the store instead, which is where it was always going to end up.
class NameEntryScreen extends StatefulWidget {
  const NameEntryScreen({
    required this.title,
    required this.onDone,
    this.initial = '',
    this.confirmLabel = 'Готово',
    this.layout = KeyboardLayout.words,
    super.key,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  /// Which keyboard to draw — an address needs punctuation a title never does.
  final KeyboardLayout layout;

  /// What the name is for. Runs before the screen closes, so whatever is
  /// behind it is already right by the time it comes back into view.
  final Future<void> Function(String name) onDone;

  @override
  State<NameEntryScreen> createState() => _NameEntryScreenState();
}

class _NameEntryScreenState extends State<NameEntryScreen> {
  late String _value = widget.initial;

  void _type(String character) => setState(() => _value += character);

  void _backspace() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  Future<void> _confirm() async {
    final name = _value.trim();
    if (name.isEmpty) return;
    await widget.onDone(name);
    if (mounted) Back.requestFrom(context);
  }

  @override
  Widget build(BuildContext context) {
    return HardwareTyping(
      onCharacter: _type,
      onBackspace: _backspace,
      child: Scaffold(
        body: SafeArea(
          // Scrollable rather than a fixed column: the keyboard is seven rows
          // tall, and with the copy above it that overflows a 1080p panel — the
          // more so once the interface scale is turned up in settings.
          child: SingleChildScrollView(
            clipBehavior: Clip.none,
            padding: EdgeInsets.fromLTRB(
              context.px(80),
              context.px(48),
              context.px(80),
              context.px(40),
            ),
            // `anchor`, because in a browser the keyboard is not drawn at all
            // and the only focusable thing left is the confirm chip — and the
            // screen still has to hold focus for `HardwareTyping` to see a
            // letter.
            child: FocusArea(
              landing: true,
              anchor: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: context.sp(34),
                      fontWeight: FontWeight.w500,
                      color: Nocturne.text,
                    ),
                  ),
                  SizedBox(height: context.px(14)),
                  Text(
                    _value.isEmpty ? 'Почніть вводити' : _value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.sp(34),
                      color: _value.isEmpty
                          ? Nocturne.neutral700
                          : Nocturne.text,
                    ),
                  ),
                  SizedBox(height: context.px(20)),
                  TypingPad(
                    onKey: _type,
                    onBackspace: _backspace,
                    onClear: () => setState(() => _value = ''),
                    layout: widget.layout,
                  ),
                  SizedBox(height: context.px(18)),
                  TvChipRow(
                    itemCount: 1,
                    builder: (context, index) => TvChip(
                      label: widget.confirmLabel,
                      selected: true,
                      enabled: _value.trim().isNotEmpty,
                      onSelect: _confirm,
                    ),
                  ),
                  SizedBox(height: context.px(14)),
                  Text(
                    'OK ввести  ·  ⌫ назад',
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
      ),
    );
  }
}

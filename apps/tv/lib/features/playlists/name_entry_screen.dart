import 'package:flutter/material.dart';

import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../../widgets/hardware_typing.dart';
import '../../widgets/dpad_keyboard.dart';

/// Types a name with the remote, and hands it back.
///
/// Same keyboard the search screen uses — a television has one way to enter
/// text, and inventing a second one would only be a second thing to learn.
class NameEntryScreen extends StatefulWidget {
  const NameEntryScreen({
    required this.title,
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

  /// Resolves with the typed name, or `null` when it was left.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initial = '',
    String confirmLabel = 'Готово',
    KeyboardLayout layout = KeyboardLayout.words,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => NameEntryScreen(
          title: title,
          initial: initial,
          confirmLabel: confirmLabel,
          layout: layout,
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return HardwareTyping(
      onCharacter: _type,
      onBackspace: _backspace,
      onClear: () => setState(() => _value = ''),
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
                    color: _value.isEmpty ? Nocturne.neutral700 : Nocturne.text,
                  ),
                ),
                SizedBox(height: context.px(20)),
                DpadKeyboard(
                  onKey: _type,
                  onBackspace: _backspace,
                  onClear: () => setState(() => _value = ''),
                ),
                SizedBox(height: context.px(18)),
                TvChipRow(
                  itemCount: 1,
                  builder: (context, index) => TvChip(
                    label: widget.confirmLabel,
                    selected: true,
                    enabled: _value.trim().isNotEmpty,
                    onSelect: () => Navigator.of(context).pop(_value.trim()),
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
    );
  }
}

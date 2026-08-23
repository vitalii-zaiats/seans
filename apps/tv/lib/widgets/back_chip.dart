import 'package:flutter/material.dart';

import '../core/sfx.dart';
import '../theme/nocturne.dart';

/// The way out of a screen where there is no BACK key to press.
///
/// A browser window and a desktop have no remote, and the shell's navigator is
/// nested — so the browser's own back button has no history to read either.
/// Without this there is no way out of a screen at all on those.
///
/// Not named `BackButton`: Flutter already has one, and the two collide on
/// import the same way `HeroMode` did.
class BackChip extends StatefulWidget {
  const BackChip({required this.onSelect, super.key});

  final VoidCallback onSelect;

  @override
  State<BackChip> createState() => _BackChipState();
}

class _BackChipState extends State<BackChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          // Not a `Focusable`, so it does not get the click for free — this is
          // the only interactive widget in the app that has to ask.
          Sfx.tap();
          widget.onSelect();
        },
        // This hangs in the shell's `Stack` rather than behind a route, so
        // there is no `Scaffold` above it to provide one — and a `Text` with
        // no `Material` ancestor is painted in Flutter's yellow
        // double-underlined debug style.
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.px(18),
              vertical: context.px(10),
            ),
            decoration: BoxDecoration(
              color: _hovered ? context.accentTint : context.surface,
              borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
              border: Border.all(
                color: _hovered ? context.accent : Nocturne.neutral800,
                width: context.px(1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back,
                  size: context.px(20),
                  color: Nocturne.text,
                ),
                SizedBox(width: context.px(8)),
                Text(
                  'Назад',
                  style: TextStyle(
                    fontSize: context.sp(16),
                    color: Nocturne.text,
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

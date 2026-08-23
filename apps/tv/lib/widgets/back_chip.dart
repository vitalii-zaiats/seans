import 'package:flutter/material.dart';

import '../theme/nocturne.dart';
import 'focusable.dart';

/// The way out of a screen where there is no BACK key to press.
///
/// A browser window and a desktop have no remote, and over a picture that goes
/// edge to edge the launcher's own way-back strip is hidden — so without this
/// there is no way out of a screen at all on those.
///
/// A [Focusable] like everything else that can be pressed, which is how the
/// only drawn exit on the web became reachable from a keyboard as well as a
/// mouse. It used to be the one interactive widget in the app that had to ask
/// for its own click and its own sound.
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      // A chip must not shift what is beside it as focus walks past.
      scaleOnFocus: 1,
      glow: false,
      onSelect: widget.onSelect,
      onFocusChange: (focused) => setState(() => _focused = focused),
      // This hangs outside every route's `Scaffold` in the shell's strip, so
      // there is nothing above it to provide a `Material` — and a `Text` with
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
            color: _focused ? context.accentTint : context.surface,
            borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
            border: Border.all(
              color: _focused ? context.accent : Nocturne.neutral800,
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
    );
  }
}

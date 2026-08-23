import '../../../core/navigate.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/labels.dart';
import '../../../core/nav_tab.dart';
import '../../../core/sfx.dart';
import '../../../platform/box_for_platform.dart';
import '../../../theme/nocturne.dart';
import '../../../widgets/focusable.dart';

/// The brand, the sections, and the clock.
class TopBar extends StatelessWidget {
  const TopBar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.link,
    super.key,
  });

  final List<NavTab> destinations;
  final NavTab selected;
  final ValueChanged<NavTab> onSelect;

  /// What the box is connected by: `ethernet`, `wifi`, `cellular` or `none`.
  final String link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.px(80),
        context.px(36),
        context.px(80),
        0,
      ),
      child: Row(
        children: [
          for (final tab in destinations) ...[
            _Destination(
              label: tab.title,
              selected: tab == selected,
              // Walking up into the row lands on the section showing now
              // rather than on Головна: the row is where you are, not a list
              // you start from.
              preferred: tab == selected,
              onSelect: () => onSelect(tab),
            ),
            SizedBox(width: context.px(28)),
          ],
          const Spacer(),
          // Only a machine that reports its connection gets a glyph for it.
          // Elsewhere the icon would sit there showing the default forever,
          // which is a claim about the network rather than a reading of it.
          if (platformBox.present) ...[
            _LinkIcon(link: link),
            SizedBox(width: context.px(16)),
          ],
          const _Clock(),
          SizedBox(width: context.px(16)),
          const _SettingsButton(),
        ],
      ),
    );
  }
}

class _Destination extends StatefulWidget {
  const _Destination({
    required this.label,
    required this.selected,
    required this.preferred,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final bool preferred;
  final VoidCallback onSelect;

  @override
  State<_Destination> createState() => _DestinationState();
}

class _DestinationState extends State<_Destination> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;

    return Focusable(
      preferred: widget.preferred,
      // A nav item must not shift its neighbours as focus walks the row.
      scaleOnFocus: 1,
      glow: false,
      // Changing section is not the same event as picking a card, so it does
      // not get the card's click.
      cue: SfxCue.navEdge,
      onSelect: widget.onSelect,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(12),
          vertical: context.px(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                fontSize: context.sp(18),
                color: active ? Nocturne.text : Nocturne.neutral600,
              ),
            ),
            SizedBox(height: context.px(5)),
            // A short accent mark stays solid — the design's rules fade, its
            // marks do not.
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: context.px(2),
              width: widget.selected ? context.px(22) : 0,
              color: context.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the box is connected by, as one glyph.
///
/// Drawn from the transport of the default network and nothing narrower — an
/// SSID would want a location permission, which is not a thing to ask a
/// television owner for in order to label an icon.
class _LinkIcon extends StatelessWidget {
  const _LinkIcon({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    final (icon, offline) = switch (link) {
      'wifi' => (Icons.wifi_rounded, false),
      'ethernet' => (Icons.settings_ethernet_rounded, false),
      'cellular' => (Icons.signal_cellular_alt_rounded, false),
      _ => (Icons.wifi_off_rounded, true),
    };

    return Icon(
      icon,
      size: context.px(22),
      color: offline ? context.accentSoft : Nocturne.neutral500,
    );
  }
}

/// Opens the launcher's own settings, which in turn offer the box's.
class _SettingsButton extends StatefulWidget {
  const _SettingsButton();

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      scaleOnFocus: 1,
      glow: false,
      onSelect: () => openRoute(context, '/settings'),
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Padding(
        padding: EdgeInsets.all(context.px(6)),
        child: Icon(
          Icons.settings_outlined,
          size: context.px(24),
          color: _focused ? context.accent : Nocturne.neutral500,
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Ticking every second would rebuild the top bar far more often than the
    // display actually changes.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    clockLabel(_now),
    style: TextStyle(fontSize: context.sp(20), color: Nocturne.neutral400),
  );
}

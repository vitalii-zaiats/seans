import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/pinned_apps_store.dart';
import '../../../core/remote/focus_area.dart';
import '../../../platform/box.dart';
import '../../../platform/box_for_platform.dart';
import '../../../theme/nocturne.dart';
import '../../../widgets/focusable.dart';

/// Apps, one press from the home screen.
///
/// Shows what was pinned; falls back to what is installed when nothing has
/// been. A row that only appears after somebody finds a hidden key is a row
/// nobody ever sees — and reaching YouTube on a fresh box should not require
/// discovering anything.
class PinnedAppsRail extends StatefulWidget {
  const PinnedAppsRail({super.key});

  @override
  State<PinnedAppsRail> createState() => _PinnedAppsRailState();
}

class _PinnedAppsRailState extends State<PinnedAppsRail> {
  final _box = platformBox;

  late final Future<List<InstalledApp>> _installed = _box.apps();

  @override
  Widget build(BuildContext context) {
    final store = context.read<PinnedAppsStore>();

    return ValueListenableBuilder<List<String>>(
      valueListenable: store.listenable,
      builder: (context, pinned, _) {
        return FutureBuilder<List<InstalledApp>>(
          future: _installed,
          builder: (context, snapshot) {
            final apps = snapshot.data;
            if (apps == null) return SizedBox(height: context.px(150));

            // Pinned order, and anything since uninstalled simply drops out.
            final byPackage = {for (final app in apps) app.package: app};
            final shown = pinned.isEmpty
                ? _defaults(apps)
                : [for (final package in pinned) ?byPackage[package]];
            if (shown.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: context.px(80)),
                  child: Text(
                    'Застосунки',
                    style: TextStyle(
                      fontSize: context.sp(22),
                      fontWeight: FontWeight.w500,
                      color: Nocturne.text,
                    ),
                  ),
                ),
                SizedBox(height: context.px(14)),
                FocusArea(
                  flow: Axis.horizontal,
                  child: SizedBox(
                    height: context.px(150),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.symmetric(horizontal: context.px(80)),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(width: context.px(16)),
                      itemBuilder: (context, index) =>
                          _PinnedTile(app: shown[index]),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// What the row shows before anybody has pinned anything.
///
/// Television-native apps first: a box has both, and a phone app sideloaded
/// onto it is far less likely to be what somebody reaches for from the sofa
/// than the one that shipped with a leanback entry.
List<InstalledApp> _defaults(List<InstalledApp> apps) {
  final ordered = [
    ...apps.where((app) => app.leanback),
    ...apps.where((app) => !app.leanback),
  ];
  return ordered.take(PinnedAppsStore.max).toList();
}

class _PinnedTile extends StatefulWidget {
  const _PinnedTile({required this.app});

  final InstalledApp app;

  @override
  State<_PinnedTile> createState() => _PinnedTileState();
}

class _PinnedTileState extends State<_PinnedTile> {
  final _box = platformBox;

  Uint8List? _art;
  bool _banner = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _loadArt();
  }

  Future<void> _loadArt() async {
    final art = await _box.art(widget.app.package);
    if (!mounted || art == null) return;
    setState(() {
      _art = art.bytes;
      _banner = art.banner;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focusable(
      scaleOnFocus: 1.05,
      onSelect: () => _box.launch(widget.app.package),
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) revealOnFocus(context, alignment: 0.08);
      },
      child: Container(
        width: context.px(_banner ? 240 : 150),
        color: context.surface,
        child: _art == null
            ? const SizedBox.shrink()
            // A banner is drawn to fill a tile; an icon keeps its own
            // proportions with the name under it.
            : _banner
            ? Image.memory(_art!, fit: BoxFit.cover)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.memory(_art!, height: context.px(64)),
                  SizedBox(height: context.px(10)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: context.px(10)),
                    child: Text(
                      widget.app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.sp(15),
                        color: _focused ? Nocturne.text : Nocturne.neutral400,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

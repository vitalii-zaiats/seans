import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'back.dart';
import 'focus_area.dart';

/// The one owner of the arrows and of "back".
///
/// **Focus is moved by hand here, not asked for through `Shortcuts`.** On the
/// Television_1080p emulator a downward `DirectionalFocusAction` does nothing
/// at all — neither the arrow bound to it nor a `NextFocusIntent` put in its
/// place — while the very same
/// `FocusTraversalGroup.of(context).inDirection(node, TraversalDirection.down)`
/// called straight from a key handler moves focus perfectly and scrolls the
/// list on the way. Sideways works either way. So the fragile path is taken
/// out of the road: every step below is a `requestFocus()` on a real node or
/// that call made directly.
///
/// Mounted in `MaterialApp.router(builder:)`, which puts it *under*
/// `WidgetsApp`'s own `Shortcuts` in the focus tree — and key events travel
/// from the focused node outwards, so this sees an arrow before
/// `DirectionalFocusAction` could. It is above the router as well, so the
/// wizard, which lives outside the launcher shell, is covered by the same
/// arbiter as everything else.
///
/// It moves focus and nothing else. What a press *means* is the screen's:
/// OK belongs to `Focusable`, a letter to `HardwareTyping`, and a seek or a
/// channel change to the `RemoteControls` of the area that is playing.
class RemoteControl extends StatefulWidget {
  const RemoteControl({required this.router, required this.child, super.key});

  /// Handed in rather than looked up: this is mounted above the router's own
  /// `InheritedGoRouter`, so `GoRouter.of` has nothing to find here.
  final GoRouter router;

  final Widget child;

  @override
  State<RemoteControl> createState() => _RemoteControlState();
}

class _RemoteControlState extends State<RemoteControl> {
  static final _moves = <LogicalKeyboardKey, RemoteMove>{
    LogicalKeyboardKey.arrowUp: RemoteMove.up,
    LogicalKeyboardKey.arrowDown: RemoteMove.down,
    LogicalKeyboardKey.arrowLeft: RemoteMove.left,
    LogicalKeyboardKey.arrowRight: RemoteMove.right,
  };

  /// What a set-top remote offers instead of the D-pad while something plays.
  ///
  /// Only ever read by an area that answers the directions itself, where there
  /// is no focusable surface below to have taken them first.
  static final _transport = <LogicalKeyboardKey, RemoteMove>{
    LogicalKeyboardKey.mediaTrackNext: RemoteMove.right,
    LogicalKeyboardKey.mediaTrackPrevious: RemoteMove.left,
  };

  /// OK, for the same areas and for the same reason.
  static final _select = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.mediaPlayPause,
  };

  /// The keys that mean "back" on a machine with no BACK key. `goBack` is
  /// deliberately not among them — see `back.dart`.
  static final _back = <LogicalKeyboardKey>{
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.backspace,
  };

  /// The areas of the last settled frame, so an area going away can be told
  /// from one that was never there.
  final _known = <RemoteArea>{};

  /// Where a modal took focus from, to be given back when it goes.
  final _returnTo = <RemoteArea, FocusNode>{};

  bool _settling = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    FocusAreas.changes.addListener(_onAreasChanged);
    _onAreasChanged();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    FocusAreas.changes.removeListener(_onAreasChanged);
    super.dispose();
  }

  /// Every area an ancestor of the focused node keeps its own note of where
  /// focus was, so "back to where I was" works at each level of nesting rather
  /// than only the innermost.
  void _onFocusChanged() {
    final node = FocusManager.instance.primaryFocus;
    if (node != null) FocusAreas.remember(node);
  }

  void _onAreasChanged() {
    if (_settling) return;
    _settling = true;
    // After the frame the areas were mounted in: taking focus during a build
    // is an assertion failure, not a subtle bug. A route transition runs for
    // 260–420 ms, so one frame is not something anybody sees.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settling = false;
      if (mounted) _settle();
    });
  }

  /// Answers "who should hold focus now" after a screen or an overlay changed.
  ///
  /// Areas rather than routes, so this is the same answer for `go`, for `push`
  /// and for something laid into a `Stack` — the idle screen used to be the
  /// third of those, and left focus nowhere at all.
  void _settle() {
    final now = FocusAreas.mounted.toSet();
    final fresh = now.difference(_known);

    for (final gone in _known.difference(now)) {
      final back = _returnTo.remove(gone);
      if (back != null && back.context != null && back.canRequestFocus) {
        back.requestFocus();
      }
    }
    _known
      ..clear()
      ..addAll(now);

    // Something that has *just* covered the screen owns the remote whatever
    // held it before, and hands it back when it goes. Only just-arrived ones:
    // a player and the panel over it are both modal, and re-reading the list
    // on every unrelated rebuild would otherwise hand the remote back down to
    // the picture under the panel.
    for (final area in FocusAreas.landings) {
      if (!area.modal || !fresh.contains(area) || area.holdsFocus) continue;
      final from = FocusAreas.held;
      if (area.enter()) {
        if (from != null) _returnTo[area] = from;
        return;
      }
    }

    if (FocusAreas.held != null) return;
    _land();
  }

  /// Puts focus somewhere it can be seen. The cure for "the remote is dead".
  bool _land() {
    for (final area in FocusAreas.landings) {
      if (area.enter()) return true;
    }
    for (final area in FocusAreas.anywhere) {
      if (area.enter()) return true;
    }
    return false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (_back.contains(key)) {
      // Down, never repeat: a held ⌫ is one press somebody has not let go of,
      // and answering the repeats would unwind the whole stack at once.
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      return Back.request(widget.router)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    final move = _moves[key];
    final from = FocusAreas.held;

    if (move != null) {
      // No focus, or focus outside every area: the next press is what brings
      // it back, rather than the remote staying dead for the session.
      if (from == null) {
        return _land() ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      _walk(FocusAreas.enclosing(from)!, from, move);
      return KeyEventResult.handled;
    }

    // Everything below belongs to a screen that is itself the control. Where
    // there is none, this is not the arbiter's key: `Focusable` has already
    // had OK, and `HardwareTyping` the letters.
    final controls = from == null
        ? null
        : FocusAreas.enclosing(from)!.controls;
    if (controls == null) return KeyEventResult.ignored;

    final transport = _transport[key];
    if (transport != null) {
      return (controls.onMove?.call(transport) ?? false)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    final select = controls.onSelect;
    if (select != null && _select.contains(key)) {
      // A key repeat is a held-down OK, not a second press.
      if (event is KeyDownEvent) select();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// One press, start to finish.
  ///
  /// The area under the ring answers first — as an action if it is the
  /// control, then as ordinary traversal inside itself. Only when it has
  /// nothing does the press bubble: out to the parent, across to the
  /// neighbour the direction points at, and into the first of those that has
  /// somewhere to land. An area with nothing focusable in it is skipped rather
  /// than swallowing the press.
  void _walk(RemoteArea start, FocusNode from, RemoteMove move) {
    if (start.controls?.onMove?.call(move) ?? false) return;
    if (start.moveWithin(from, move)) return;

    var area = start;
    while (true) {
      if (area.modal) return;
      final parent = area.parent;
      if (parent == null) return;
      for (final next in parent.childrenTowards(area, move)) {
        if (next.enter()) return;
      }
      area = parent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      debugLabel: 'remote',
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}

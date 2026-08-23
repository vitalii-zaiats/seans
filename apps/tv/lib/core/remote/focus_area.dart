import 'package:flutter/widgets.dart';

/// One press of the D-pad, whatever key on the remote produced it.
enum RemoteMove {
  up(TraversalDirection.up, Axis.vertical, forward: false),
  down(TraversalDirection.down, Axis.vertical, forward: true),
  left(TraversalDirection.left, Axis.horizontal, forward: false),
  right(TraversalDirection.right, Axis.horizontal, forward: true);

  const RemoteMove(this.direction, this.axis, {required this.forward});

  /// What Flutter's own traversal calls this.
  final TraversalDirection direction;

  /// How areas would have to be laid out for this to move between them.
  final Axis axis;

  /// Towards the end of that axis — down the screen, or across to its right.
  final bool forward;
}

/// A screen that *is* the control, rather than a list of things to focus.
///
/// On a player → means ten seconds, not the next tile, and OK means pause. An
/// area carrying these always holds a node of its own, so a press always has
/// somewhere to land — which is precisely what the live player lacked: its
/// root `Focus` had no node, and one stray focus change left the remote with
/// nothing to talk to.
@immutable
class RemoteControls {
  const RemoteControls({this.onMove, this.onSelect});

  /// `true` when the direction was an action here, and so must not move focus.
  final bool Function(RemoteMove move)? onMove;

  /// OK, and whatever else on the remote means it.
  final VoidCallback? onSelect;
}

/// What a focusable surface may say to the area it sits in.
///
/// Deliberately two methods and no more: a widget can ask to be where focus
/// lands first, and it cannot reach the scope, read it, or focus it.
abstract interface class FocusAreaScope {
  /// "If you have no memory of your own, land on me."
  void claimPreferred(FocusNode node);

  void releasePreferred(FocusNode node);
}

/// One area as the arbiter sees it. Nothing else in the app holds one.
abstract interface class RemoteArea {
  bool get landing;
  bool get anchor;
  bool get modal;
  RemoteControls? get controls;

  /// Whether focus may enter at all — see `_covered` in `focus_area.dart` for
  /// the flag a covered route is actually read off.
  bool get available;

  /// The area this one sits in, or `null` at the top.
  RemoteArea? get parent;

  /// Whether the focus of the moment is inside here.
  bool get holdsFocus;

  /// How many areas this one is nested in.
  int get depth;

  /// Moves focus onto something real in here, and says whether it could.
  ///
  /// Never the scope: see [FocusArea].
  bool enter();

  /// Ordinary traversal, held to this area's own scope.
  bool moveWithin(FocusNode from, RemoteMove move);

  /// The areas beside [from] that a press in this direction would reach, in
  /// the order it would reach them.
  List<RemoteArea> childrenTowards(RemoteArea from, RemoteMove move);
}

/// An area of the screen the remote can be handed.
///
/// **The only owner of a `FocusScopeNode` in this app, and the scope is
/// private.** `FocusScopeNode.requestFocus()` on a scope that has never held
/// focus focuses *the scope itself* rather than anything inside it: nothing is
/// ringed, and — worse — the arrows then have nothing to traverse from. One
/// press of UP was enough to kill the remote for the rest of the session,
/// measured on the Television_1080p emulator. A scope nobody can reach is a
/// scope nobody can focus.
///
/// A screen declares its areas and nothing else: which way its parts are laid
/// out, where focus should land, whether the arrows may leave. `RemoteControl`
/// reads those declarations and does the moving.
class FocusArea extends StatefulWidget {
  const FocusArea({
    required this.child,
    this.flow = Axis.vertical,
    this.landing = false,
    this.anchor = false,
    this.modal = false,
    this.controls,
    this.onEntered,
    super.key,
  });

  final Widget child;

  /// How the areas *inside* this one are laid out. Read only to pick the
  /// neighbour a press leaving one of them should reach.
  final Axis flow;

  /// Focus lands here when a screen or an overlay appears.
  final bool landing;

  /// With nothing focusable inside, the area takes focus on its own node.
  ///
  /// So a screen made only of text still has focus somewhere, and the
  /// `HardwareTyping` above it still sees letters.
  final bool anchor;

  /// A press never leaves: the bubble stops here.
  final bool modal;

  /// The area answers the directions and OK itself.
  final RemoteControls? controls;

  /// Fires when the *arbiter* moved focus in here — not when focus drifted in
  /// on its own, which on a box is an air mouse crossing the area.
  final VoidCallback? onEntered;

  /// The area this widget sits in, for a surface that wants to ask something
  /// of it. There is nothing here to focus a scope with.
  static FocusAreaScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AreaHandle>()?.area;

  @override
  State<FocusArea> createState() => _FocusAreaState();
}

class _FocusAreaState extends State<FocusArea>
    implements FocusAreaScope, RemoteArea {
  /// Private, and that is the whole point of the class. See [FocusArea].
  ///
  /// `skipTraversal`, and this is load-bearing rather than tidiness: Flutter's
  /// own traversal does not descend into a nested scope but it does offer the
  /// scope itself as a candidate, so a screen holding both a button and an
  /// area — a wizard step with a choice tile over a row of chips — could walk
  /// straight onto a scope and focus it. That is the dead remote this class
  /// exists to prevent. Crossing between areas is the arbiter's job, and
  /// nobody else's.
  final FocusScopeNode _scope = FocusScopeNode(
    debugLabel: 'area',
    skipTraversal: true,
  );

  /// Where focus rests when there is nothing inside to rest on.
  ///
  /// `skipTraversal`, so it is never a stop on the way round: it exists to be
  /// somewhere a press can land, not somewhere the arrows walk to.
  final FocusNode _own = FocusNode(
    debugLabel: 'area anchor',
    skipTraversal: true,
  );

  /// The last real node that held focus in here.
  FocusNode? _remembered;

  /// Claims from the surfaces inside, in the order they were made.
  final _preferred = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    FocusAreas._add(this);
  }

  @override
  void dispose() {
    FocusAreas._remove(this);
    _own.dispose();
    _scope.dispose();
    super.dispose();
  }

  // FocusAreaScope ──────────────────────────────────────────────────────────

  @override
  void claimPreferred(FocusNode node) {
    if (!_preferred.contains(node)) _preferred.add(node);
  }

  @override
  void releasePreferred(FocusNode node) => _preferred.remove(node);

  // RemoteArea ──────────────────────────────────────────────────────────────

  @override
  bool get landing => widget.landing;

  @override
  bool get anchor => widget.anchor;

  @override
  bool get modal => widget.modal;

  @override
  RemoteControls? get controls => widget.controls;

  @override
  bool get available => _scope.canRequestFocus && !_covered(_scope);

  @override
  RemoteArea? get parent {
    for (final ancestor in _scope.ancestors) {
      final area = FocusAreas._byScope[ancestor];
      if (area != null) return area;
    }
    return null;
  }

  @override
  int get depth {
    var count = 0;
    for (final ancestor in _scope.ancestors) {
      if (FocusAreas._byScope.containsKey(ancestor)) count++;
    }
    return count;
  }

  @override
  bool get holdsFocus {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return false;
    return identical(focused, _own) ||
        identical(focused, _scope) ||
        focused.ancestors.contains(_scope);
  }

  @override
  bool enter() {
    final node = _entry();
    if (node == null) return false;
    node.requestFocus();
    widget.onEntered?.call();
    return true;
  }

  /// Where a press coming in from outside should land.
  ///
  /// In order: where it was last, what asked for it, the first thing the
  /// traversal would reach — and only then the area's own node, and only for
  /// an area that said it would take it. Anything else answers "not me", and
  /// the arbiter carries on to the next area.
  FocusNode? _entry() {
    // An area that answers the remote itself always holds its own node. There
    // is nowhere else in it a press should land — and a surface that happens
    // to be drawn inside one, like the mouse's way out of a player in a
    // browser, must not be able to take OK away from the transport.
    if (widget.controls != null) return _own;

    final remembered = _remembered;
    if (remembered != null && _usable(remembered)) return remembered;

    for (final node in _preferred) {
      if (_usable(node)) return node;
    }

    for (final node in _scope.traversalDescendants) {
      if (_usable(node)) return node;
    }

    if (widget.anchor || widget.controls != null) return _own;
    return null;
  }

  /// Whether [node] is somewhere in here that focus could actually go.
  bool _usable(FocusNode node) {
    if (node.context == null || node is FocusScopeNode) return false;
    if (!node.canRequestFocus) return false;
    for (final ancestor in node.ancestors) {
      if (identical(ancestor, _scope)) return true;
      if (ancestor is FocusScopeNode && !FocusAreas._ours(ancestor)) {
        if (ancestor.skipTraversal) return false;
      }
    }
    // Not in this area at all — a remembered node that has moved on.
    return false;
  }

  @override
  bool moveWithin(FocusNode from, RemoteMove move) {
    final where = from.context;
    if (where == null) return false;
    // Directly, not through `Shortcuts` and `DirectionalFocusAction`: see
    // `RemoteControl`. The search runs inside `from`'s nearest scope, which is
    // this area's own or something nested in it, so a move can never wander
    // out of the area behind the arbiter's back.
    return FocusTraversalGroup.of(where).inDirection(from, move.direction);
  }

  @override
  List<RemoteArea> childrenTowards(RemoteArea from, RemoteMove move) {
    if (move.axis != widget.flow) return const [];

    final children = _children();
    final at = children.indexWhere((area) => identical(area, from));
    if (at < 0) return const [];

    final ahead = move.forward
        ? children.sublist(at + 1)
        : children.reversed.skip(children.length - at).toList();
    return [
      for (final area in ahead)
        if (area.available) area,
    ];
  }

  /// The areas directly inside this one, in the order somebody sees them.
  ///
  /// Ordered by where they are on the panel rather than by when they were
  /// built: that is what a person is aiming at, and it survives a list being
  /// rebuilt in a different order.
  List<_FocusAreaState> _children() {
    final mine = <_FocusAreaState>[
      for (final area in FocusAreas._areas)
        if (identical(area.parent, this)) area,
    ];
    final at = {
      for (final area in mine) area: area._along(widget.flow),
    };
    mine.sort((a, b) {
      final byPlace = at[a]!.compareTo(at[b]!);
      return byPlace != 0 ? byPlace : a._order.compareTo(b._order);
    });
    return mine;
  }

  /// How far down (or across) the panel this area starts.
  double _along(Axis flow) {
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return double.maxFinite;
    }
    final at = object.localToGlobal(Offset.zero);
    return flow == Axis.vertical ? at.dy : at.dx;
  }

  /// When this area was mounted — the tie-break when two share a position.
  /// Stamped on registration rather than on first read, so it is mount order
  /// and not the order somebody happened to ask.
  int _order = 0;

  void _remember(FocusNode node) => _remembered = node;

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _scope,
      child: _AreaHandle(
        area: this,
        child: Focus(
          focusNode: _own,
          // An ancestor of everything in the area and a stop for nothing:
          // `_own` is only ever focused deliberately, by `enter`.
          child: widget.child,
        ),
      ),
    );
  }
}

class _AreaHandle extends InheritedWidget {
  const _AreaHandle({required this.area, required super.child});

  final FocusAreaScope area;

  @override
  bool updateShouldNotify(_AreaHandle old) => !identical(old.area, area);
}

/// Every area on screen, for the one widget that is allowed to move focus.
///
/// A registry rather than a walk of the widget tree: the arbiter is asked on
/// a key press, and the answer has to be the areas as they are *now* —
/// including an overlay that went up between two presses.
abstract final class FocusAreas {
  static final _areas = <_FocusAreaState>[];
  static final _byScope = <FocusScopeNode, _FocusAreaState>{};
  static final _changes = _Bell();
  static int _nextOrder = 0;

  /// Fires when an area is mounted or unmounted — which is when focus may
  /// need landing or handing back.
  static Listenable get changes => _changes;

  static List<RemoteArea> get mounted => List<RemoteArea>.of(_areas);

  /// The innermost area [node] sits in, or `null` when it sits in none.
  static RemoteArea? enclosing(FocusNode node) {
    for (final ancestor in node.ancestors) {
      final area = _byScope[ancestor];
      if (area != null) return area;
    }
    return null;
  }

  /// Records [node] as "where I was" in every area it sits in, so coming back
  /// works at each level of nesting rather than only the innermost.
  static void remember(FocusNode node) {
    if (node is FocusScopeNode) return;
    for (final ancestor in node.ancestors) {
      _byScope[ancestor]?._remember(node);
    }
  }

  /// Where focus should be offered, deepest first.
  ///
  /// Deepest, because the innermost thing on screen is the newest: an overlay
  /// wins over the screen behind it without anybody ranking them.
  static List<RemoteArea> get landings => _sorted(
    (area) => area.available && area.landing,
  );

  /// Everything focus could go, in the same order — the last resort.
  static List<RemoteArea> get anywhere => _sorted((area) => area.available);

  static List<RemoteArea> _sorted(bool Function(_FocusAreaState) keep) {
    final chosen = [
      for (final area in _areas)
        if (keep(area)) area,
    ];
    final depths = {for (final area in chosen) area: area.depth};
    chosen.sort((a, b) {
      final byDepth = depths[b]!.compareTo(depths[a]!);
      return byDepth != 0 ? byDepth : a._order.compareTo(b._order);
    });
    return List<RemoteArea>.of(chosen);
  }

  /// One of this app's own scopes, rather than a route's or Flutter's.
  static bool _ours(FocusScopeNode scope) => _byScope.containsKey(scope);

  /// The focus of the moment, if it is somewhere a press can start from.
  ///
  /// A scope is not: focusing one is the state this whole design exists to
  /// make unreachable, and when Flutter's own route handling leaves focus on
  /// one, the next press is what heals it. Neither is a node in an area a
  /// route has since covered.
  static FocusNode? get held {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode) return null;
    if (!node.canRequestFocus) return null;
    final area = enclosing(node);
    if (area == null || !area.available) return null;
    return node;
  }

  static void _add(_FocusAreaState area) {
    area._order = _nextOrder++;
    _areas.add(area);
    _byScope[area._scope] = area;
    _changes.ring();
  }

  static void _remove(_FocusAreaState area) {
    _areas.remove(area);
    _byScope.remove(area._scope);
    _changes.ring();
  }
}

/// Whether a route above [from] has taken it out of play.
///
/// Flutter does **not** clear `canRequestFocus` on the scope of a route that is
/// merely covered — it only does that for the few frames one is being popped.
/// What it does set, on every route scope that is not the top one, is
/// `skipTraversal`. So that is the flag to read, and reading it is what keeps
/// the arrows out of the rails behind the half-transparent details page
/// without anybody writing "am I the current route" anywhere.
///
/// Our own scopes skip traversal too, and deliberately — so they are stepped
/// over here by name rather than by flag.
bool _covered(FocusNode from) {
  for (final ancestor in from.ancestors) {
    if (ancestor is! FocusScopeNode || FocusAreas._ours(ancestor)) continue;
    if (ancestor.skipTraversal || !ancestor.canRequestFocus) return true;
  }
  return false;
}

/// A `Listenable` with nothing to read — only the fact that something changed.
class _Bell extends ChangeNotifier {
  void ring() => notifyListeners();
}

/// What one press of the remote does, as a set of assertions rather than a
/// walk round an emulator.
///
/// The arbiter is plain logic over the focus tree — it needs no box, no player
/// and no network — so every measured failure that provoked this design can be
/// pinned here: the dead remote after one press of UP, the tabs stealing a
/// move that belonged to the rail above, an empty area swallowing a press, an
/// overlay leaving focus nowhere, and BACK counting twice.
library;

import 'dart:ui' show KeyData, KeyEventType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:seans_tv/core/remote/back.dart';
import 'package:seans_tv/core/remote/focus_area.dart';
import 'package:seans_tv/core/remote/remote_control.dart';

class Item extends StatelessWidget {
  const Item({required this.label, this.preferred = false, super.key});
  final String label;
  final bool preferred;

  @override
  Widget build(BuildContext context) => _Item(label: label, preferred: preferred);
}

class _Item extends StatefulWidget {
  const _Item({required this.label, required this.preferred});
  final String label;
  final bool preferred;
  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  late final node = FocusNode(debugLabel: widget.label);
  FocusAreaScope? _area;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _area = FocusArea.of(context);
    if (widget.preferred) _area?.claimPreferred(node);
  }

  @override
  void dispose() {
    _area?.releasePreferred(node);
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    debugLabel: widget.label,
    child: SizedBox(width: 100, height: 40, child: Text(widget.label)),
  );
}

String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

late GoRouter router;

Future<void> pump(WidgetTester tester, Widget child) async {
  router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: child)),
      GoRoute(path: '/deep', builder: (_, _) => const Scaffold(body: Text('x'))),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      builder: (context, child) => RemoteControl(router: router, child: child!),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bar and content, both ways, on the remembered node', (t) async {
    await pump(
      t,
      FocusArea(
        child: Column(
          children: [
            const FocusArea(
              flow: Axis.horizontal,
              child: Row(children: [Item(label: 'tab1'), Item(label: 'tab2')]),
            ),
            Expanded(
              child: FocusArea(
                anchor: true,
                landing: true,
                child: Column(
                  children: const [Item(label: 'a'), Item(label: 'b')],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    expect(focused(), 'a');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(focused(), 'b', reason: 'within the content area');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focused(), 'a');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focused(), 'tab1', reason: 'up out of the content into the bar');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(focused(), 'tab2');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(focused(), 'a', reason: 'back to where the content was left');
  });

  testWidgets('rail to rail, not straight to the bar', (t) async {
    await pump(
      t,
      FocusArea(
        child: Column(
          children: const [
            FocusArea(
              flow: Axis.horizontal,
              child: Row(children: [Item(label: 'tab')]),
            ),
            FocusArea(
              flow: Axis.horizontal,
              landing: true,
              child: Row(children: [Item(label: 'r1a'), Item(label: 'r1b')]),
            ),
            FocusArea(
              flow: Axis.horizontal,
              child: Row(children: [Item(label: 'r2a')]),
            ),
          ],
        ),
      ),
    );
    expect(focused(), 'r1a');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(focused(), 'r2a');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focused(), 'r1a', reason: 'the rail above, not the bar');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focused(), 'tab');
  });

  testWidgets('an area with nothing in it is skipped', (t) async {
    await pump(
      t,
      FocusArea(
        child: Column(
          children: const [
            FocusArea(
              flow: Axis.horizontal,
              child: Row(children: [Item(label: 'top')]),
            ),
            FocusArea(child: SizedBox(width: 10, height: 10)),
            FocusArea(
              flow: Axis.horizontal,
              landing: true,
              child: Row(children: [Item(label: 'bottom')]),
            ),
          ],
        ),
      ),
    );
    expect(focused(), 'bottom');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focused(), 'top');
  });

  testWidgets('no landing lands on the first area that has something', (
    t,
  ) async {
    await pump(
      t,
      FocusArea(
        child: Column(
          children: const [
            FocusArea(child: SizedBox(width: 10, height: 10)),
            FocusArea(
              flow: Axis.horizontal,
              child: Row(children: [Item(label: 'first')]),
            ),
            FocusArea(
              flow: Axis.horizontal,
              child: Row(children: [Item(label: 'second')]),
            ),
          ],
        ),
      ),
    );
    expect(focused(), 'first');
  });

  testWidgets('preferred wins over the first descendant', (t) async {
    await pump(
      t,
      const FocusArea(
        landing: true,
        child: Column(
          children: [Item(label: 'one'), Item(label: 'two', preferred: true)],
        ),
      ),
    );
    expect(focused(), 'two');
  });

  testWidgets('a modal takes the remote and gives it back', (t) async {
    var showing = false;
    await pump(
      t,
      StatefulBuilder(
        builder: (context, setState) => Stack(
          children: [
            FocusArea(
              landing: true,
              child: Column(
                children: [
                  const Item(label: 'a'),
                  _Button(
                    label: 'open',
                    onTap: () => setState(() => showing = true),
                  ),
                ],
              ),
            ),
            if (showing)
              FocusArea(
                modal: true,
                landing: true,
                child: Column(
                  children: [
                    _Button(
                      label: 'close',
                      onTap: () => setState(() => showing = false),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    expect(focused(), 'a');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(focused(), 'open');

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(focused(), 'close', reason: 'the modal took it');

    await t.tap(find.text('close'));
    await t.pumpAndSettle();
    expect(focused(), 'open', reason: 'handed back where it came from');
  });

  testWidgets('no focus at all: the next arrow brings it back', (t) async {
    await pump(
      t,
      const FocusArea(
        landing: true,
        child: Column(children: [Item(label: 'a'), Item(label: 'b')]),
      ),
    );
    FocusManager.instance.primaryFocus!.unfocus();
    await t.pumpAndSettle();
    expect(focused(), isNot('a'));

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(focused(), 'a');
  });

  testWidgets('goBack does nothing; escape goes back once', (t) async {
    await pump(
      t,
      const FocusArea(landing: true, child: Column(children: [Item(label: 'a')])),
    );
    router.push('/deep');
    await t.pumpAndSettle();
    expect(router.state.matchedLocation, '/deep');

    // Straight into the binding: `flutter_test`'s key simulator has no scan
    // code for BACK on any platform map, and this is the key whose absence is
    // the point.
    // Its replacement is a *handler* on `HardwareKeyboard`, and the focus
    // tree is fed from the key event manager rather than from there — so this
    // is the only way in for a key the simulator has no scan code for.
    // ignore: deprecated_member_use
    final manager = ServicesBinding.instance.keyEventManager;
    // ignore: deprecated_member_use
    manager.handleKeyData(
      KeyData(
        timeStamp: Duration.zero,
        type: KeyEventType.down,
        physical: PhysicalKeyboardKey.browserBack.usbHidUsage,
        logical: LogicalKeyboardKey.goBack.keyId,
        character: null,
        synthesized: false,
      ),
    );
    await t.pumpAndSettle();
    expect(router.state.matchedLocation, '/deep', reason: 'goBack is unbound');

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(router.state.matchedLocation, '/');
  });

  testWidgets('a BackStop takes the press; floor lets it through', (t) async {
    var took = 0;
    await pump(
      t,
      BackStop(
        onBack: () {
          took++;
          return BackAnswer.took;
        },
        child: const FocusArea(
          landing: true,
          child: Column(children: [Item(label: 'a')]),
        ),
      ),
    );
    router.push('/deep');
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pumpAndSettle();
    expect(took, 1);
    expect(router.state.matchedLocation, '/deep', reason: 'router untouched');
  });

  testWidgets('floor answers false', (t) async {
    await pump(
      t,
      BackStop(
        onBack: () => BackAnswer.floor,
        child: const FocusArea(
          landing: true,
          child: Column(children: [Item(label: 'a')]),
        ),
      ),
    );
    expect(Back.request(router), isFalse);
  });
}

class _Button extends StatefulWidget {
  const _Button({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  late final node = FocusNode(debugLabel: widget.label);
  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    debugLabel: widget.label,
    child: GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(width: 100, height: 40, child: Text(widget.label)),
    ),
  );
}

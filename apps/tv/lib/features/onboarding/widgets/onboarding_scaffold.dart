import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/remote/focus_area.dart';
import '../../../data/settings_store.dart';
import '../../../theme/nocturne.dart';
import '../../../widgets/back_chip.dart';
import '../../../widgets/focusable.dart';
import '../onboarding_cubit.dart';

/// The frame every setup screen sits in: a step counter, a heading, the body,
/// and a line at the foot saying what the remote does.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    required this.title,
    required this.child,
    this.step,
    this.totalSteps,
    this.subtitle,
    this.hint,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// 1-based; omitted on screens that are not part of the count.
  final int? step;
  final int? totalSteps;

  final String? hint;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<OnboardingCubit>();
    final canGoBack = cubit.state.canGoBack;

    // A remote has a BACK key and needs nothing drawn for it; a browser window
    // and a desktop have neither that nor a route to pop, and without this
    // there would be no way back at all. The same split the launcher's own
    // way-back strip makes, for the same reason.
    final chip = canGoBack && Settings.pointerByDefault;

    // Said rather than drawn, on the machines where BACK is a key. The foot of
    // the screen already lists what the remote does here — but whether BACK
    // does anything depends on how somebody arrived, which is not something a
    // screen can write into its own hint.
    final foot = canGoBack && !chip
        ? [?hint, 'BACK повернутись'].join('  ·  ')
        : hint;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.px(120),
            context.px(64),
            context.px(120),
            context.px(48),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (step != null && totalSteps != null) ...[
                _Steps(current: step!, total: totalSteps!),
                SizedBox(height: context.px(28)),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: context.sp(46),
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  color: Nocturne.text,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: context.px(14)),
                SizedBox(
                  width: context.px(1100),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: context.sp(20),
                      height: 1.5,
                      color: Nocturne.neutral400,
                    ),
                  ),
                ),
              ],
              SizedBox(height: context.px(36)),
              // The body is where every answer lives, and `anchor` covers the
              // two screens that are pure copy with a QR code on them: even
              // there the remote has somewhere to be.
              Expanded(
                child: FocusArea(landing: true, anchor: true, child: child),
              ),
              // The way back keeps the company of the line that says what the
              // remote does: both are the same sentence — how to leave this
              // screen — and the top of every setup screen belongs to its
              // heading.
              if (chip || foot != null) ...[
                SizedBox(height: context.px(16)),
                FocusArea(
                  flow: Axis.horizontal,
                  child: Row(
                    children: [
                      if (chip) ...[
                        BackChip(onSelect: cubit.back),
                        SizedBox(width: context.px(20)),
                      ],
                      if (foot != null)
                        Expanded(
                          child: Text(
                            foot,
                            style: TextStyle(
                              fontSize: context.sp(14),
                              color: Nocturne.neutral700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Short accent marks, one per step — the design's rules fade, its marks stay
/// solid.
class _Steps extends StatelessWidget {
  const _Steps({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          Container(
            width: context.px(i == current ? 34 : 18),
            height: context.px(3),
            color: i <= current ? context.accent : Nocturne.neutral800,
          ),
          SizedBox(width: context.px(8)),
        ],
        SizedBox(width: context.px(10)),
        Text(
          '$current / $total',
          style: TextStyle(
            fontSize: context.sp(14),
            letterSpacing: context.px(2),
            color: Nocturne.neutral600,
          ),
        ),
      ],
    );
  }
}

/// One answer: a heading, a sentence saying what it means, and nothing hidden
/// behind it.
class ChoiceTile extends StatefulWidget {
  const ChoiceTile({
    required this.title,
    required this.description,
    required this.onSelect,
    this.preferred = false,
    this.icon,
    this.note,
    super.key,
  });

  final String title;
  final String description;
  final VoidCallback onSelect;
  final bool preferred;
  final IconData? icon;

  /// A caveat worth reading before choosing, drawn apart from the description.
  final String? note;

  @override
  State<ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<ChoiceTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.px(12)),
      child: Focusable(
        preferred: widget.preferred,
        scaleOnFocus: 1,
        onSelect: widget.onSelect,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) revealOnFocus(context, alignment: 0.2);
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: context.px(28),
            vertical: context.px(22),
          ),
          decoration: BoxDecoration(
            color: _focused ? context.accentTint : context.surface,
            border: Border.all(
              color: _focused ? context.accent : Nocturne.neutral800,
              width: context.px(1),
            ),
            borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: context.px(26),
                  color: _focused ? context.accent : Nocturne.neutral600,
                ),
                SizedBox(width: context.px(18)),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: context.sp(24),
                        color: Nocturne.text,
                      ),
                    ),
                    SizedBox(height: context.px(6)),
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: context.sp(17),
                        height: 1.45,
                        color: Nocturne.neutral400,
                      ),
                    ),
                    if (widget.note != null) ...[
                      SizedBox(height: context.px(8)),
                      Text(
                        widget.note!,
                        style: TextStyle(
                          fontSize: context.sp(15),
                          height: 1.4,
                          color: context.accentSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

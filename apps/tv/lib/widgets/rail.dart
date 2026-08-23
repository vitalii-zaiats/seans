import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

/// A titled horizontal row of tiles.
///
/// The list is `shrinkWrap`-free and lazily built: a rail can hold a whole
/// catalogue page, and a television has the least memory of anything Flutter
/// runs on.
class Rail extends StatelessWidget {
  const Rail({
    required this.itemCount,
    required this.itemBuilder,
    this.title,
    this.height,
    super.key,
  });

  /// Omitted where the row already sits under a heading of its own.
  final String? title;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: EdgeInsets.only(
              left: context.px(80),
              bottom: context.px(14),
            ),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: context.sp(22),
                fontWeight: FontWeight.w500,
                color: Nocturne.text,
              ),
            ),
          ),
        SizedBox(
          height: height ?? context.px(372),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // A focused tile scales up; a clipping viewport would shave its
            // accent ring, and the page padding leaves room for the growth.
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(horizontal: context.px(80)),
            itemCount: itemCount,
            separatorBuilder: (_, _) => SizedBox(width: context.px(20)),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

/// The line along the foot of the home screen that says what the remote does.
class KeyHints extends StatelessWidget {
  const KeyHints({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.px(80),
        vertical: context.px(18),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: context.sp(14),
          color: Nocturne.neutral700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

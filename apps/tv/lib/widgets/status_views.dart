import 'package:flutter/material.dart';

import '../core/remote/focus_area.dart';
import '../theme/nocturne.dart';
import 'focusable.dart';

/// A first load, before there is anything to draw.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      Center(child: CircularProgressIndicator(color: context.accent));
}

/// A failure, with the one action a remote can take.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // An area, and an anchoring one: a failure with nothing to press is still
    // a screen the remote has to be somewhere on, or the next arrow has
    // nothing to push off from.
    return FocusArea(
      landing: true,
      anchor: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: context.px(56),
              color: Nocturne.neutral700,
            ),
            SizedBox(height: context.px(18)),
            Text(
              message,
              style: TextStyle(
                fontSize: context.sp(22),
                color: Nocturne.neutral400,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: context.px(26)),
              _RetryButton(onSelect: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatefulWidget {
  const _RetryButton({required this.onSelect});

  final VoidCallback onSelect;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      preferred: true,
      onSelect: widget.onSelect,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(28),
          vertical: context.px(14),
        ),
        decoration: BoxDecoration(
          color: _focused
              ? context.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          border: Border.all(color: context.accent, width: context.px(1)),
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Text(
          'Спробувати ще раз',
          style: TextStyle(fontSize: context.sp(18), color: Nocturne.text),
        ),
      ),
    );
  }
}

/// Nothing matched.
class EmptyView extends StatelessWidget {
  const EmptyView({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => FocusArea(
    landing: true,
    anchor: true,
    child: Center(
      child: Text(
        message,
        style: TextStyle(fontSize: context.sp(20), color: Nocturne.neutral600),
      ),
    ),
  );
}

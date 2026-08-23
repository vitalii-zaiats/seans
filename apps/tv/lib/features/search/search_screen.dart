import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/navigate.dart';
import '../../core/labels.dart';
import '../../core/remote/focus_area.dart';
import '../../theme/nocturne.dart';
import '../../widgets/focusable.dart';
import '../../widgets/hardware_typing.dart';
import '../../widgets/poster_image.dart';
import '../../widgets/status_views.dart';
import 'search_cubit.dart';
import '../../widgets/typing_pad.dart';

/// Keyboard on the left, results on the right, updating as the query grows.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchCubit>();

    return HardwareTyping(
      onCharacter: cubit.type,
      onBackspace: cubit.backspace,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              context.px(80),
              context.px(48),
              context.px(80),
              context.px(40),
            ),
            // Keyboard and results, side by side and stated as such. Where
            // there is a real keyboard the left half draws nothing, so the area
            // has nothing to land on and is skipped — the platform fork that
            // used to decide this by hand is gone, and `anchor` keeps focus on
            // the screen either way so `HardwareTyping` above still sees the
            // letters.
            child: FocusArea(
              flow: Axis.horizontal,
              anchor: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: context.px(700),
                    // Scrollable for the same reason the name entry is: seven
                    // rows of keys plus the query line overflow a 1080p panel
                    // once the interface scale is turned up.
                    child: FocusArea(
                      landing: true,
                      child: SingleChildScrollView(
                        clipBehavior: Clip.none,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _QueryLine(),
                            SizedBox(height: context.px(28)),
                            TypingPad(
                              onKey: cubit.type,
                              onBackspace: cubit.backspace,
                              onClear: cubit.clear,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: context.px(60)),
                  const Expanded(child: _Results()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueryLine extends StatelessWidget {
  const _QueryLine();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchCubit, SearchState>(
      buildWhen: (previous, current) => previous.query != current.query,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ПОШУК',
              style: TextStyle(
                fontSize: context.sp(13),
                letterSpacing: context.px(3),
                color: context.accent,
              ),
            ),
            SizedBox(height: context.px(10)),
            Text(
              state.query.isEmpty ? 'Почніть вводити' : state.query,
              style: TextStyle(
                fontSize: context.sp(40),
                fontWeight: FontWeight.w500,
                color: state.query.isEmpty
                    ? Nocturne.neutral700
                    : Nocturne.text,
              ),
            ),
            SizedBox(height: context.px(10)),
            // A rule that fades at its ends rather than stopping cleanly.
            Container(
              height: context.px(1),
              width: context.px(640),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Nocturne.divider,
                    Nocturne.divider,
                    Colors.transparent,
                  ],
                  stops: const [0, 0.08, 0.92, 1],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Results extends StatelessWidget {
  const _Results();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        if (state.status.isFailure) {
          return ErrorView(message: state.error ?? 'Пошук не вдався');
        }
        if (state.isTooShort) {
          return const EmptyView(message: 'Введіть принаймні дві літери');
        }
        if (state.status.isLoading && state.results.isEmpty) {
          return const LoadingView();
        }
        if (state.results.isEmpty) {
          return const EmptyView(message: 'Нічого не знайшлося');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${state.results.length} результатів',
              style: TextStyle(
                fontSize: context.sp(15),
                color: Nocturne.neutral600,
              ),
            ),
            SizedBox(height: context.px(16)),
            Expanded(
              child: FocusArea(
                child: ListView.separated(
                  clipBehavior: Clip.none,
                  itemCount: state.results.length,
                  separatorBuilder: (_, _) => SizedBox(height: context.px(10)),
                  itemBuilder: (context, index) =>
                      _ResultRow(result: state.results[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResultRow extends StatefulWidget {
  const _ResultRow({required this.result});

  final SearchResult result;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.result.card;

    return Focusable(
      scaleOnFocus: 1.01,
      onSelect: () => openRoute(context, '/title/${card.slug}'),
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) revealOnFocus(context, alignment: 0.3);
      },
      child: Container(
        color: _focused ? context.surface : Colors.transparent,
        padding: EdgeInsets.all(context.px(10)),
        child: Row(
          children: [
            SizedBox(
              width: context.px(64),
              height: context.px(90),
              child: PosterImage(
                url: card.posterUrl,
                borderRadius: BorderRadius.circular(context.px(4)),
              ),
            ),
            SizedBox(width: context.px(16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The server says which part of the title the query hit;
                  // drawing it in the accent saves reading the whole row.
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final span in widget.result.nameSpans())
                          TextSpan(
                            text: span.text,
                            style: TextStyle(
                              color: span.matched
                                  ? context.accentSoft
                                  : Nocturne.text,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: context.sp(22)),
                  ),
                  SizedBox(height: context.px(4)),
                  Text(
                    metaLine([
                      card.type == null ? null : contentTypeLabel(card.type!),
                      card.yearLabel,
                      card.imdbMark == null
                          ? null
                          : '★ ${ratingLabel(card.imdbMark)}',
                    ]),
                    style: TextStyle(
                      fontSize: context.sp(16),
                      color: Nocturne.neutral600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

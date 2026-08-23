import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/navigate.dart';
import '../../core/labels.dart';
import '../../core/remote/focus_area.dart';
import '../../theme/nocturne.dart';
import '../../widgets/focusable.dart';
import '../../widgets/status_views.dart';

/// The browse menu: sections down the left, then that section's genres and
/// years.
///
/// The same three-part shape the website's Каталог menu has, which is the one
/// layout a D-pad walks without thinking — left and right move between the
/// three regions, up and down within one.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<CatalogFilters> _filters = context
      .read<SuperMoviesApi>()
      .catalogFilters();

  ContentType _type = ContentType.movie;

  void _open({String? genre, String? year}) {
    openRoute(
      context,
      Uri(
        path: '/catalog/${_type.slug}',
        queryParameters: {'genre': ?genre, 'year': ?year},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.px(80),
            context.px(48),
            context.px(80),
            context.px(40),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Каталог',
                style: TextStyle(
                  fontSize: context.sp(38),
                  fontWeight: FontWeight.w500,
                  color: Nocturne.text,
                ),
              ),
              SizedBox(height: context.px(28)),
              Expanded(
                child: FutureBuilder<CatalogFilters>(
                  future: _filters,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LoadingView();
                    }
                    if (snapshot.hasError) {
                      return ErrorView(
                        message: 'Не вдалося завантажити каталог',
                        onRetry: () => setState(() {
                          _filters = context
                              .read<SuperMoviesApi>()
                              .catalogFilters();
                        }),
                      );
                    }

                    final section = snapshot.data?[_type];
                    // The three-part shape the class docstring describes, now
                    // said rather than left to be inferred: one area across,
                    // three areas in it, and ← → is the step between them.
                    return FocusArea(
                      flow: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: context.px(300),
                            child: FocusArea(
                              landing: true,
                              child: _Sections(
                                selected: _type,
                                counts: snapshot.data,
                                onSelect: (type) =>
                                    setState(() => _type = type),
                              ),
                            ),
                          ),
                          SizedBox(width: context.px(40)),
                          Expanded(
                            flex: 3,
                            child: _Column(
                              title: 'Жанри',
                              child: section == null
                                  ? const SizedBox.shrink()
                                  : FocusArea(
                                      child: _Genres(
                                        genres: section.allGenres,
                                        onSelect: (slug) => _open(genre: slug),
                                      ),
                                    ),
                            ),
                          ),
                          SizedBox(width: context.px(40)),
                          Expanded(
                            child: _Column(
                              title: 'Роки',
                              child: section == null
                                  ? const SizedBox.shrink()
                                  : FocusArea(
                                      child: _Years(
                                        years: section.years,
                                        onSelect: (slug) => _open(year: slug),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: context.sp(17),
            color: Nocturne.neutral600,
          ),
        ),
        SizedBox(height: context.px(14)),
        Expanded(child: child),
      ],
    );
  }
}

/// The five sections, and how much is in each.
class _Sections extends StatelessWidget {
  const _Sections({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final ContentType selected;
  final CatalogFilters? counts;
  final ValueChanged<ContentType> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      clipBehavior: Clip.none,
      children: [
        for (final type in ContentType.values)
          Padding(
            padding: EdgeInsets.only(bottom: context.px(8)),
            child: _SectionRow(
              label: contentTypeLabel(type),
              count: counts?[type]?.totalCount,
              selected: type == selected,
              preferred: type == selected,
              onSelect: () => onSelect(type),
            ),
          ),
      ],
    );
  }
}

class _SectionRow extends StatefulWidget {
  const _SectionRow({
    required this.label,
    required this.count,
    required this.selected,
    required this.preferred,
    required this.onSelect,
  });

  final String label;
  final int? count;
  final bool selected;
  final bool preferred;
  final VoidCallback onSelect;

  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;

    return Focusable(
      preferred: widget.preferred,
      scaleOnFocus: 1,
      glow: false,
      onSelect: widget.onSelect,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        // Moving through the sections swaps the two columns beside them, the
        // way the website's menu does.
        if (focused && !widget.selected) widget.onSelect();
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(20),
          vertical: context.px(14),
        ),
        decoration: BoxDecoration(
          color: widget.selected ? context.accentTint : Colors.transparent,
          border: Border.all(
            color: active ? context.accent : Colors.transparent,
            width: context.px(1),
          ),
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: context.sp(22),
                  color: active ? Nocturne.text : Nocturne.neutral500,
                ),
              ),
            ),
            if (widget.count != null)
              Text(
                '${widget.count}',
                style: TextStyle(
                  fontSize: context.sp(15),
                  color: Nocturne.neutral700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Genres, laid out in as many columns as the space allows.
class _Genres extends StatelessWidget {
  const _Genres({required this.genres, required this.onSelect});

  final List<Genre> genres;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      clipBehavior: Clip.none,
      child: Wrap(
        spacing: context.px(10),
        runSpacing: context.px(8),
        children: [
          for (final genre in genres)
            _MenuItem(label: genre.name, onSelect: () => onSelect(genre.slug)),
        ],
      ),
    );
  }
}

class _Years extends StatelessWidget {
  const _Years({required this.years, required this.onSelect});

  final List<YearOption> years;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      clipBehavior: Clip.none,
      child: Wrap(
        spacing: context.px(10),
        runSpacing: context.px(8),
        children: [
          for (final year in years)
            _MenuItem(label: year.name, onSelect: () => onSelect(year.slug)),
        ],
      ),
    );
  }
}

/// One genre or year: plain text until focus, which is all the site's own menu
/// gives them and all a wall of forty needs.
class _MenuItem extends StatefulWidget {
  const _MenuItem({required this.label, required this.onSelect});

  final String label;
  final VoidCallback onSelect;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      scaleOnFocus: 1,
      glow: false,
      onSelect: widget.onSelect,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) revealOnFocus(context, alignment: 0.3);
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(14),
          vertical: context.px(10),
        ),
        decoration: BoxDecoration(
          color: _focused ? context.accentTint : Colors.transparent,
          border: Border.all(
            color: _focused ? context.accent : Colors.transparent,
            width: context.px(1),
          ),
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: context.sp(18),
            color: _focused ? Nocturne.text : Nocturne.neutral400,
          ),
        ),
      ),
    );
  }
}

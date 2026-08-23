import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/navigate.dart';
import '../../core/labels.dart';
import '../../theme/nocturne.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/status_views.dart';
import 'catalog_cubit.dart';

/// What one section, genre or year holds — a grid that keeps loading as it is
/// walked down.
class CatalogResultsScreen extends StatefulWidget {
  const CatalogResultsScreen({super.key});

  @override
  State<CatalogResultsScreen> createState() => _CatalogResultsScreenState();
}

class _CatalogResultsScreenState extends State<CatalogResultsScreen> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Starts the next page while about two rows are still below the fold, so
  /// walking down the grid rarely meets a spinner.
  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - context.px(700)) {
      context.read<CatalogCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<CatalogCubit, CatalogState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.px(80),
                    context.px(44),
                    context.px(80),
                    context.px(20),
                  ),
                  child: _Heading(state: state),
                ),
                Expanded(
                  child: _Body(state: state, controller: _controller),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.state});

  final CatalogState state;

  @override
  Widget build(BuildContext context) {
    final section = state.sectionFilters;
    final genre = state.genreSlug == null
        ? null
        : section?.genreBySlug(state.genreSlug!)?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metaLine([contentTypeLabel(state.type), genre, state.yearSlug]),
          style: TextStyle(
            fontSize: context.sp(34),
            fontWeight: FontWeight.w500,
            color: Nocturne.text,
          ),
        ),
        if (state.meta != null) ...[
          SizedBox(height: context.px(6)),
          Text(
            '${state.meta!.total} тайтлів',
            style: TextStyle(
              fontSize: context.sp(16),
              color: Nocturne.neutral600,
            ),
          ),
        ],
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.controller});

  final CatalogState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CatalogCubit>();

    if (state.status.isFailure) {
      return ErrorView(
        message: state.error ?? 'Не вдалося завантажити каталог',
        onRetry: cubit.retry,
      );
    }
    if (state.status.isLoading && state.items.isEmpty) {
      return const LoadingView();
    }
    if (state.status.isSuccess && state.items.isEmpty) {
      return const EmptyView(message: 'За цими фільтрами нічого немає');
    }

    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          // Room above the first row: a focused tile grows, and the viewport
          // clips at its own top edge whatever the grid's clipBehaviour says.
          padding: EdgeInsets.fromLTRB(
            context.px(80),
            context.px(18),
            context.px(80),
            0,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: context.px(220),
              childAspectRatio: 0.52,
              crossAxisSpacing: context.px(20),
              mainAxisSpacing: context.px(24),
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final card = state.items[index];
              return PosterTile(
                card: card,
                autofocus: index == 0,
                onSelect: () => openRoute(context, '/title/${card.slug}'),
              );
            }, childCount: state.items.length),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: context.px(90),
            child: Center(
              child: state.loadingMore
                  ? SizedBox(
                      width: context.px(26),
                      height: context.px(26),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.accent,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

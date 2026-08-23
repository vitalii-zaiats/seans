import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/navigate.dart';
import '../../core/error_message.dart';
import '../../core/router.dart';

/// Opens the player for a title whose seasons are already loaded.
///
/// The route is pushed before anything is resolved, so the crossfade starts on
/// the same frame as the button press — the stream lookup happens behind the
/// blurred still the player lands on.
Future<void> openPlayer(
  BuildContext context, {
  required ContentDetails details,
  required Season? season,
  int? episode,
  Duration? resumeAt,
}) {
  final playable =
      season ?? details.latestPlayableSeason ?? details.firstSeason;
  if (playable == null) return Future.value();

  return openRoute<void>(
    context,
    '/title/${details.slug}/play',
    // The title, its seasons and where to resume are objects, not something an
    // address can carry — so the address says which film, and this says the
    // rest. Opened cold it lands on the title's page instead, which is a
    // reasonable place for a link to a film to go.
    extra: PlayerArgs(
      details: details,
      season: playable,
      episode: episode,
      resumeAt: resumeAt,
    ),
  );
}

/// The same, from a card — which carries no seasons, so the detail payload has
/// to be fetched first.
///
/// A lookup that fails opens the title's page instead of showing an error over
/// the home screen: it is one button press from there to the same place, and
/// the page can say more about why.
Future<void> openPlayerForSlug(
  BuildContext context, {
  required String slug,
  Duration? resumeAt,
  int? season,
  int? episode,
}) async {
  final api = context.read<SuperMoviesApi>();
  final messenger = ScaffoldMessenger.of(context);

  ContentDetails details;
  try {
    details = await api.content(slug);
  } on ApiException catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    return;
  }

  if (!context.mounted) return;

  final target = season == null
      ? null
      : details.seasons.where((s) => s.number == season).firstOrNull;

  if (!details.isPlayable) {
    await openRoute<void>(context, '/title/$slug');
    return;
  }

  await openPlayer(
    context,
    details: details,
    season: target,
    episode: episode,
    resumeAt: resumeAt,
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

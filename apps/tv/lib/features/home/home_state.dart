import 'package:equatable/equatable.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/load_status.dart';
import '../../data/library_store.dart';

/// One half-watched title, with the card that draws it.
class ResumeEntry extends Equatable {
  const ResumeEntry({required this.card, required this.progress});

  final ContentCard card;
  final WatchProgress progress;

  /// `С2 · Е5 · 42%` for a series, just the percentage for a film — where
  /// somebody stopped is the whole point of the rail, and for a series that
  /// means which episode as much as how far in.
  String get label {
    final percent = '${(progress.fraction * 100).round()}%';
    final season = progress.season;
    final episode = progress.episode;
    if (episode == null) return percent;
    return [if (season != null) 'С$season', 'Е$episode', percent].join(' · ');
  }

  @override
  List<Object?> get props => [card.slug, progress.position, progress.updatedAt];
}

/// A titled row on the home screen.
class HomeRail extends Equatable {
  const HomeRail({required this.title, required this.items});

  final String title;
  final List<ContentCard> items;

  bool get isEmpty => items.isEmpty;

  @override
  List<Object?> get props => [title, items];
}

class HomeState extends Equatable {
  const HomeState({
    this.status = LoadStatus.initial,
    this.hero = const [],
    this.rails = const [],
    this.resume = const [],
    this.heroIndex = 0,
    this.link = 'ethernet',
    this.error,
  });

  final LoadStatus status;

  /// The slider titles behind the split hero.
  final List<ContentCard> hero;

  /// Everything below the hero, in display order.
  final List<HomeRail> rails;

  /// The "Continue watching" row, which carries progress the others don't.
  final List<ResumeEntry> resume;

  /// Which hero title is showing.
  final int heroIndex;

  /// What the box is connected by, for the corner of the top bar.
  final String link;

  final String? error;

  ContentCard? get heroCard =>
      hero.isEmpty ? null : hero[heroIndex.clamp(0, hero.length - 1)];

  /// Where somebody got to in the hero title, if anywhere.
  WatchProgress? get heroProgress {
    final card = heroCard;
    if (card == null) return null;
    for (final entry in resume) {
      if (entry.card.slug == card.slug) return entry.progress;
    }
    return null;
  }

  bool get isOffline => link == 'none';

  HomeState copyWith({
    LoadStatus? status,
    List<ContentCard>? hero,
    List<HomeRail>? rails,
    List<ResumeEntry>? resume,
    int? heroIndex,
    String? link,
    String? error,
  }) => HomeState(
    status: status ?? this.status,
    hero: hero ?? this.hero,
    rails: rails ?? this.rails,
    resume: resume ?? this.resume,
    heroIndex: heroIndex ?? this.heroIndex,
    link: link ?? this.link,
    error: error,
  );

  @override
  List<Object?> get props => [
    status,
    hero,
    rails,
    resume,
    heroIndex,
    link,
    error,
  ];
}

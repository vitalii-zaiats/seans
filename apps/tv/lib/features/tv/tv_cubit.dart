import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:iptv/iptv.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/load_status.dart';
import '../../data/iptv_store.dart';
import '../../data/sweet_tv_store.dart';
import 'live_channel.dart';

class TvState extends Equatable {
  const TvState({
    this.status = LoadStatus.initial,
    this.channels = const [],
    this.groups = const [],
    this.group,
    this.error,
  });

  final LoadStatus status;

  /// Every channel the loaded sources hold, in source order.
  final List<LiveChannel> channels;

  /// Group names to show as chips, with the starred pseudo-group first.
  final List<String> groups;

  /// Which group is showing; `null` means everything.
  final String? group;

  final String? error;

  /// The label the starred channels hide behind. Not a real group.
  static const favourites = '★ Обране';

  /// What the grid shows right now.
  List<LiveChannel> visible(Set<String> starred) {
    if (group == null) return channels;
    if (group == favourites) {
      return [
        for (final channel in channels)
          if (starred.contains(channel.id)) channel,
      ];
    }
    return [
      for (final channel in channels)
        if (channel.group == group) channel,
    ];
  }

  TvState copyWith({
    LoadStatus? status,
    List<LiveChannel>? channels,
    List<String>? groups,
    String? group,
    bool clearGroup = false,
    String? error,
  }) => TvState(
    status: status ?? this.status,
    channels: channels ?? this.channels,
    groups: groups ?? this.groups,
    group: clearGroup ? null : (group ?? this.group),
    error: error,
  );

  @override
  List<Object?> get props => [status, channels, groups, group, error];
}

class TvCubit extends Cubit<TvState> {
  TvCubit(this._loader, this._store, this._api, this._sweetStore)
    : super(const TvState());

  final IptvLoader _loader;
  final IptvStore _store;
  final SuperMoviesApi _api;
  final SweetTvStore _sweetStore;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));

    final channels = <LiveChannel>[];
    final seen = <String>{};
    String? failure;

    // sweet.tv first: it is a curated list that always works, and a first run
    // should not open on somebody's public M3U full of dead entries.
    if (_sweetStore.enabled) {
      try {
        final catalogue = await _api.channels();
        final titles = {
          for (final category in catalogue.categories)
            if (!category.isAll) category.id: category.title,
        };

        for (final channel in catalogue.items) {
          final live = SweetLiveChannel(
            channel,
            categoryTitle: _titleFor(channel, titles),
          );
          if (seen.add(live.id)) channels.add(live);
        }
      } on ApiException catch (error) {
        failure = error.message;
      }
    }

    // Several playlists can be subscribed to at once, and they overlap — the
    // same channel appears in a national list and a regional one. First wins.
    for (final source in _store.sources()) {
      try {
        final playlist = await _loader.load(source);
        for (final channel in playlist.channels) {
          final live = PlaylistChannel(channel);
          if (seen.add(live.id)) channels.add(live);
        }
      } on IptvException catch (error) {
        failure = error.message;
      }
    }

    if (isClosed) return;

    if (channels.isEmpty) {
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          error: failure ?? 'Списки порожні',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: LoadStatus.success,
        channels: channels,
        groups: [
          TvState.favourites,
          ...{
            for (final channel in channels)
              if (channel.group != null) channel.group!,
          },
        ],
        // Opens on everything rather than on a group, because a first run has
        // nothing starred and an empty screen reads as broken.
        clearGroup: true,
      ),
    );
  }

  void showGroup(String? group) {
    if (group == state.group) return;
    emit(state.copyWith(group: group, clearGroup: group == null));
  }

  /// A playable URL for [channel].
  ///
  /// For a playlist entry that is the URL it already carries. For sweet.tv it
  /// is a request: what comes back is a lease with a session in it, so this is
  /// asked again on every open rather than remembered.
  ///
  /// The plain-http address is preferred where the answer offers one. Not a
  /// casual downgrade: the stitching host's certificate chain ends in a SHA-1
  /// root that Android refuses outright, so https there plays nowhere on a box.
  /// See `TvStream.plainUrl`.
  Future<String> streamUrl(LiveChannel channel) async => switch (channel) {
    PlaylistChannel(:final channel) => channel.url,
    SweetLiveChannel(:final channel) => await _sweetUrl(channel.id),
  };

  Future<String> _sweetUrl(int channelId) async {
    // A browser cannot read the stitched playlist — its host answers no
    // `access-control-allow-origin` — so on the web the addresses come back
    // pointing at `/stream` instead. A box asks for them untouched and plays
    // them host to viewer.
    final stream = await _api.stream(channelId, useProxy: kIsWeb);
    // And on the web `plainUrl` is the wrong one to prefer: it is the same
    // stream over plain http, which exists because Android rejects the
    // stitching host's certificate chain. A page served over https cannot load
    // it at all.
    return kIsWeb ? stream.url : (stream.plainUrl ?? stream.url);
  }

  /// What is on this channel and what follows, when the source knows.
  ///
  /// One small file per channel per day, which is what makes it reasonable to
  /// ask for the channel somebody is actually watching and no others.
  Future<TvSchedule?> scheduleFor(LiveChannel channel) async {
    if (channel is! SweetLiveChannel) return null;
    try {
      return await _api.schedule(channel.channel.id);
    } on ApiException {
      // A missing programme guide is not worth interrupting playback for.
      return null;
    }
  }

  /// The channel after [current] within what is on screen, for the arrows in
  /// the player. Wraps round.
  LiveChannel? next(LiveChannel current, {required int step}) {
    final list = state.visible(_store.favourites);
    if (list.isEmpty) return null;

    final index = list.indexWhere((channel) => channel.id == current.id);
    if (index < 0) return list.first;
    return list[(index + step) % list.length];
  }

  /// The first category that is not the catch-all — what a chip should say.
  static String? _titleFor(TvChannel channel, Map<int, String> titles) {
    for (final id in channel.categories) {
      if (titles[id] case final title?) return title;
    }
    return null;
  }
}

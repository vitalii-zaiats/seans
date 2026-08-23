import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/home_rails.dart';
import '../../core/nav_tab.dart';
import '../../platform/box_for_platform.dart';
import '../../data/iptv_store.dart';
import '../../data/network_probe.dart';
import '../../data/onboarding_store.dart';
import '../../data/startup.dart';
import '../../data/settings_store.dart';
import '../../data/steam_store.dart';
import '../../data/sweet_tv_store.dart';

/// The screens first run walks through, in order.
enum OnboardingStep {
  welcome,

  /// Whether to be remembered at all.
  ///
  /// Asked first, and that is the whole point of the order: it is the only
  /// question whose answer the app cannot guess, and until it is answered there
  /// is nothing honest to tell the server. Everything after it — which sections
  /// to carry, which channel sources — is a preference, and a preference can
  /// wait behind a decision.
  account,

  /// Only reached by choosing to pair now.
  pairing,

  /// Which catalogue sections this box should carry.
  content,

  /// Whether live television is wanted at all, and from where.
  tv,
  tvSources,

  /// Whether the games section is wanted.
  fun,

  support,

  /// Only reached by choosing to share the connection. Separate from
  /// [support] on purpose: consent to that has to be given on its own screen,
  /// not collected by picking an item off a list.
  bandwidthConsent,

  network,
  done,
}

class OnboardingViewState extends Equatable {
  const OnboardingViewState({
    this.step = OnboardingStep.welcome,
    this.trail = const [],
    this.answers = const OnboardingState(),
    this.report,
    this.probing = false,
    this.settling = false,
    this.sections = _allSections,
    this.wantsTv = true,
    this.tvSources = _allTvSources,
    this.wantsFun = true,
  });

  /// Everything on to begin with: the wizard asks what to *take away*, which
  /// is a shorter conversation than asking what to add.
  ///
  /// Spelled out rather than built from [HomeRailId], because a default has to
  /// be a constant and a loop is not one. `catalogueSections` below is the
  /// derived list, and a test holds the two together.
  static const _allSections = {
    'movies',
    'serials',
    'cartoonMovies',
    'cartoonSeries',
    'anime',
  };

  /// The sections the wizard offers, in the order the home screen shows them.
  static List<HomeRailId> get catalogueSections => [
    for (final rail in HomeRailId.values)
      if (rail.type != null) rail,
  ];

  static const _allTvSources = {sweetSource, playlistSource};

  /// sweet.tv's free channels.
  static const sweetSource = 'sweet';

  /// The built-in public M3U lists.
  static const playlistSource = 'playlists';

  /// Catalogue sections that are on, by [HomeRailId.id].
  final Set<String> sections;

  final bool wantsTv;

  /// Which channel sources are on, when [wantsTv].
  final Set<String> tvSources;

  final bool wantsFun;

  final OnboardingStep step;

  /// The screens walked to get to [step], oldest first — what BACK unwinds.
  ///
  /// A trail rather than the rule read backwards. Which screen comes next is
  /// decided in half a dozen places, by what the box can do and by what has
  /// already been answered; the same conditions spelled out in reverse would be
  /// a second set to keep in step. Where somebody actually came from is not a
  /// guess.
  final List<OnboardingStep> trail;

  /// Whether there is a screen behind this one.
  bool get canGoBack => trail.isNotEmpty;

  final OnboardingState answers;

  /// Filled in once the network step has run.
  final NetworkReport? report;

  final bool probing;

  /// The account question has been answered and the server has not replied yet.
  ///
  /// Two round trips on the anonymous path — forget, then announce — and which
  /// screen comes next cannot be decided until they land, because it depends on
  /// what the server says this build may carry. So the question stays on screen
  /// and says it is working, rather than the wizard guessing and moving.
  final bool settling;

  OnboardingViewState copyWith({
    OnboardingStep? step,
    List<OnboardingStep>? trail,
    OnboardingState? answers,
    NetworkReport? report,
    bool? probing,
    bool? settling,
    Set<String>? sections,
    bool? wantsTv,
    Set<String>? tvSources,
    bool? wantsFun,
  }) => OnboardingViewState(
    step: step ?? this.step,
    trail: trail ?? this.trail,
    answers: answers ?? this.answers,
    report: report ?? this.report,
    probing: probing ?? this.probing,
    settling: settling ?? this.settling,
    sections: sections ?? this.sections,
    wantsTv: wantsTv ?? this.wantsTv,
    tvSources: tvSources ?? this.tvSources,
    wantsFun: wantsFun ?? this.wantsFun,
  );

  @override
  List<Object?> get props => [
    step,
    trail,
    answers.completed,
    answers.account,
    answers.support,
    answers.bandwidthConsent,
    report?.ip,
    report?.megabitsPerSecond,
    probing,
    settling,
    sections,
    wantsTv,
    tvSources,
    wantsFun,
  ];
}

/// Walks first run, and writes down what it settled.
class OnboardingCubit extends Cubit<OnboardingViewState> {
  OnboardingCubit(
    this._store,
    this._startup,
    this._probe,
    this._settings,
    this._sweet,
    this._iptv,
    this._steam,
  ) : super(const OnboardingViewState());

  final OnboardingStore _store;
  final Startup _startup;
  final NetworkProbe _probe;
  final SettingsStore _settings;
  final SweetTvStore _sweet;
  final IptvStore _iptv;
  final SteamStore _steam;

  void start() => _go(OnboardingStep.account);

  /// Moves to [step], writing down where it was left.
  ///
  /// Every forward move in the wizard goes through here, which is the whole of
  /// what makes BACK work: the trail is built by walking it, so a screen that
  /// was skipped on the way down is skipped on the way back up without anybody
  /// having to say so twice.
  void _go(OnboardingStep step, {OnboardingState? answers}) {
    emit(
      state.copyWith(
        step: step,
        answers: answers,
        trail: [...state.trail, state.step],
      ),
    );
    _arrived(step);
  }

  /// Moves to [step] without leaving a mark.
  ///
  /// For the screen that is on the way through rather than on the way: pairing
  /// is entered from the account question and, however it ends, BACK from what
  /// follows belongs to that question and not to a code that has since been
  /// spent or abandoned.
  void _replace(OnboardingStep step, {OnboardingState? answers}) {
    emit(state.copyWith(step: step, answers: answers));
    _arrived(step);
  }

  /// Work a screen starts merely by being reached.
  ///
  /// In one place rather than at each `_go`: the connection check can now be
  /// arrived at from four directions — straight after the TV question on a
  /// machine with no launcher half, or after support, or after the bandwidth
  /// consent — and a measurement that only ran on three of them would look
  /// like a screen that sometimes forgets to load.
  ///
  /// The web has nothing to measure here: it is shown the install offer
  /// instead, because "how fast is this box and where is it seen from" is a
  /// question about a box.
  void _arrived(OnboardingStep step) {
    if (step == OnboardingStep.network && !kIsWeb) unawaited(runProbe());
  }

  /// Back to the screen this one was reached from.
  ///
  /// Nothing is undone on the way. Every answer is written where it is given
  /// and walking forward again writes over it, so a step revisited and
  /// confirmed a second time settles the same thing twice rather than leaving
  /// half of it behind.
  void back() {
    if (!state.canGoBack) return;
    final trail = [...state.trail];
    final step = trail.removeLast();
    emit(state.copyWith(step: step, trail: trail));
  }

  /// Adds or removes one catalogue section.
  ///
  /// The last one cannot be taken away: a box with no sections at all has an
  /// empty home screen and no way to say why.
  void toggleSection(String id) {
    final next = {...state.sections};
    if (!next.remove(id)) {
      next.add(id);
    } else if (next.isEmpty) {
      return;
    }
    emit(state.copyWith(sections: next));
  }

  /// Writes the sections and moves on.
  ///
  /// A section switched off here is a row the home screen never asks the API
  /// for — the saving is the round trip, not the widget.
  Future<void> confirmSections() async {
    for (final rail in HomeRailId.values) {
      if (rail.type == null) continue;
      await _settings.setRail(rail.id, shown: state.sections.contains(rail.id));
    }
    _go(_startup.allows(NavTab.tv.id) ? OnboardingStep.tv : _afterTv);
  }

  Future<void> chooseTv({required bool wanted}) async {
    emit(state.copyWith(wantsTv: wanted));
    if (wanted) {
      _go(OnboardingStep.tvSources);
      return;
    }

    await _applyTv();
    _go(_afterTv);
  }

  void toggleTvSource(String id) {
    final next = {...state.tvSources};
    if (!next.remove(id)) next.add(id);
    emit(state.copyWith(tvSources: next));
  }

  Future<void> confirmTvSources() async {
    // Every source off is the same answer as "no television", and saying so
    // beats leaving an empty tab behind.
    if (state.tvSources.isEmpty) {
      emit(state.copyWith(wantsTv: false));
    }
    await _applyTv();
    _go(_afterTv);
  }

  /// Cloud gaming opens somebody else's app and Steam wants the local network,
  /// so the question only means something on a machine that can do either.
  /// Asking it anywhere else collects an answer nothing will act on.
  OnboardingStep get _afterTv =>
      platformBox.present ? OnboardingStep.fun : OnboardingStep.network;

  /// The questions this build actually asks, in order — what `3 / 6` counts.
  ///
  /// Derived rather than written on each screen. The flow already skips whole
  /// questions depending on the machine and on what the server allows, and a
  /// screen that numbers itself cannot know that: a browser run used to count
  /// 1, 2, 3, 3, 5, 6, because the screen it skipped had taken 4 with it.
  ///
  /// `pairing`, `tvSources` and `bandwidthConsent` are deliberately absent —
  /// each is a second page of the question before it and shares its number.
  List<OnboardingStep> get _asked => [
    OnboardingStep.account,
    if (_startup.allows(NavTab.catalog.id)) OnboardingStep.content,
    if (_startup.allows(NavTab.tv.id)) OnboardingStep.tv,
    // Both need a launcher half: one opens other people's apps, the other
    // sells idle bandwidth a browser tab does not have.
    if (platformBox.present) ...[OnboardingStep.fun, OnboardingStep.support],
    OnboardingStep.network,
  ];

  /// Which number [step] wears, 1-based. Zero for a page that shares one.
  int numberOf(OnboardingStep step) => _asked.indexOf(step) + 1;

  int get stepCount => _asked.length;

  Future<void> chooseFun({required bool wanted}) async {
    emit(state.copyWith(wantsFun: wanted));

    await _settings.setTab(NavTab.fun.id, shown: wanted);
    // Nothing to find means nothing to look for: the network scan goes quiet
    // with the section it feeds.
    await _steam.setEnabled(wanted);

    _go(OnboardingStep.support);
  }

  Future<void> _applyTv() async {
    final on = state.wantsTv;
    await _settings.setTab(NavTab.tv.id, shown: on);
    await _settings.setRail(HomeRailId.tv.id, shown: on);
    await _sweet.setEnabled(
      on && state.tvSources.contains(OnboardingViewState.sweetSource),
    );
    await _iptv.setUsesDefaults(
      on && state.tvSources.contains(OnboardingViewState.playlistSource),
    );
  }

  /// The first question, and the only one whose answer leaves this box.
  ///
  /// Anonymous and guest both go straight on; pairing takes a detour. Either
  /// way the launch is announced here and nowhere else — this is the moment
  /// there is finally something honest to say, and what comes back decides
  /// which of the questions after it are even worth asking.
  Future<void> chooseAccount(AccountMode mode) async {
    final answers = state.answers.copyWith(account: mode);
    // Where the answer was given. Compared again at the end rather than assumed:
    // announcing is a request over somebody's home line and BACK is one press,
    // so whoever pressed it while this was in flight is answering the question
    // again, and moving them off that screen now would undo a decision they are
    // still making.
    final asked = state.step;

    if (mode == AccountMode.linked) {
      // The QR screen *is* the answer to this one, so it can be shown at once.
      _go(OnboardingStep.pairing, answers: answers);
    } else {
      // The other two do not pass through pairing, and they used to: the screen
      // was pushed for every answer and swapped out again once the server
      // replied, so anybody choosing anonymous or guest saw a QR code flash up
      // and vanish. It was never their screen — it was the wait, wearing the
      // wrong face.
      emit(state.copyWith(answers: answers, settling: true));
    }

    await _store.save(answers);

    if (mode == AccountMode.anonymous) {
      // Somebody may be going back through the wizard after having been a
      // guest, so this is not a no-op: it deletes the account and drops the id.
      await _startup.forget();
    }
    await _startup.announce(remembered: mode != AccountMode.anonymous);

    if (isClosed) return;
    // Pairing is its own screen with its own cubit — see `features/pairing`.
    // This one only decides that it is where the wizard goes next.
    if (mode == AccountMode.linked) return;

    if (state.step != asked) {
      // They walked off while this was in flight. Drop the spinner on the way
      // out, or the question keeps it the next time it is opened.
      emit(state.copyWith(settling: false));
      return;
    }
    // `_go`, not `_replace`: the trail used to be written by the hop into
    // pairing, and without that hop this is what puts the account question
    // where BACK can find it.
    _go(_afterAccount, answers: answers);
    emit(state.copyWith(settling: false));
  }

  /// Carry on with the account the phone just handed over.
  void finishPairing() => _replace(_afterAccount);

  /// Leaves pairing without an account — the box stays usable either way.
  void skipPairing() {
    final answers = state.answers.copyWith(account: AccountMode.guest);
    _replace(_afterAccount, answers: answers);
    _store.save(answers);
  }

  /// Where the wizard goes once the server has answered.
  ///
  /// A build the shop will not let carry a catalogue has no sections to choose
  /// between, and asking anyway would collect an answer nothing can act on.
  OnboardingStep get _afterAccount {
    if (_startup.allows(NavTab.catalog.id)) return OnboardingStep.content;
    if (_startup.allows(NavTab.tv.id)) return OnboardingStep.tv;
    return _afterTv;
  }

  Future<void> chooseSupport(SupportChoice choice) async {
    // Picking "share my connection" only moves to the consent screen; the flag
    // itself is set there, by an answer to a specific question.
    final answers = state.answers.copyWith(
      support: choice,
      bandwidthConsent: choice == SupportChoice.bandwidth
          ? state.answers.bandwidthConsent
          : false,
    );
    _go(
      choice == SupportChoice.bandwidth
          ? OnboardingStep.bandwidthConsent
          : OnboardingStep.network,
      answers: answers,
    );
    await _store.save(answers);
  }

  /// The answer to the consent screen. Declining drops the support choice too,
  /// so nothing is left half-agreed.
  Future<void> answerBandwidthConsent({required bool agreed}) async {
    final answers = state.answers.copyWith(
      support: agreed ? SupportChoice.bandwidth : SupportChoice.none,
      bandwidthConsent: agreed,
    );
    _go(OnboardingStep.network, answers: answers);
    await _store.save(answers);
  }

  Future<void> runProbe() async {
    emit(state.copyWith(probing: true));
    final report = await _probe.run();
    if (isClosed) return;
    emit(state.copyWith(report: report, probing: false));
  }

  void showDone() => _go(OnboardingStep.done);

  /// Marks first run as over. Until this lands the flow starts again on the
  /// next boot, which is the right way for an interrupted setup to fail.
  Future<void> finish() async {
    final answers = state.answers.copyWith(completed: true);
    emit(state.copyWith(answers: answers));
    await _store.save(answers);
  }
}

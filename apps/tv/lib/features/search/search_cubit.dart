import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/error_message.dart';
import '../../core/load_status.dart';

class SearchState extends Equatable {
  const SearchState({
    this.status = LoadStatus.initial,
    this.query = '',
    this.results = const [],
    this.error,
  });

  final LoadStatus status;
  final String query;
  final List<SearchResult> results;
  final String? error;

  /// The endpoint answers nothing below two characters, and so does this.
  bool get isTooShort => query.trim().length < 2;

  SearchState copyWith({
    LoadStatus? status,
    String? query,
    List<SearchResult>? results,
    String? error,
  }) => SearchState(
    status: status ?? this.status,
    query: query ?? this.query,
    results: results ?? this.results,
    error: error,
  );

  @override
  List<Object?> get props => [status, query, results, error];
}

class SearchCubit extends Cubit<SearchState> {
  SearchCubit(this._api) : super(const SearchState());

  final SuperMoviesApi _api;

  Timer? _debounce;

  /// Every keystroke lands here, but only the last one in a burst reaches the
  /// network — a D-pad keyboard produces a lot of them, and the endpoint has no
  /// business seeing a request per letter.
  static const _settle = Duration(milliseconds: 300);

  /// Guards against an earlier, slower query overwriting a later one.
  int _requestId = 0;

  void type(String character) => _setQuery(state.query + character);

  void backspace() {
    if (state.query.isEmpty) return;
    _setQuery(state.query.substring(0, state.query.length - 1));
  }

  void clear() => _setQuery('');

  void _setQuery(String query) {
    emit(state.copyWith(query: query));
    _debounce?.cancel();

    if (state.isTooShort) {
      emit(state.copyWith(status: LoadStatus.initial, results: const []));
      return;
    }

    emit(state.copyWith(status: LoadStatus.loading));
    _debounce = Timer(_settle, _run);
  }

  Future<void> _run() async {
    final token = ++_requestId;
    final query = state.query;

    try {
      final results = await _api.search(query, limit: 20);
      if (isClosed || token != _requestId) return;
      emit(state.copyWith(status: LoadStatus.success, results: results));
    } on ApiException catch (error) {
      if (isClosed || token != _requestId) return;
      emit(
        state.copyWith(status: LoadStatus.failure, error: describeError(error)),
      );
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}

/// Where a piece of async state currently stands.
enum LoadStatus {
  initial,
  loading,
  success,
  failure;

  bool get isInitial => this == LoadStatus.initial;
  bool get isLoading => this == LoadStatus.loading;
  bool get isSuccess => this == LoadStatus.success;
  bool get isFailure => this == LoadStatus.failure;
}

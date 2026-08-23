import 'exceptions.dart';

/// A decoded JSON object.
typedef JsonMap = Map<String, dynamic>;

/// Tolerant read helpers used by every `fromJson` in this package.
///
/// Nullable getters return `null` for a missing field, a JSON `null` or a value
/// of an unexpected type — the client stays usable when the API grows or
/// loosens a field. Non-nullable getters throw [ApiSerializationException]
/// naming the field, because a missing required field means the model can no
/// longer be trusted.
extension JsonMapReader on JsonMap {
  Never _fail(String key, String expected, {String? owner}) {
    final where = owner == null ? key : '$owner.$key';
    throw ApiSerializationException(
      'expected $expected at `$where`, got ${this[key].runtimeType}',
    );
  }

  String requireString(String key, {String? owner}) {
    final value = this[key];
    if (value is String) return value;
    _fail(key, 'String', owner: owner);
  }

  String? stringOrNull(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  int requireInt(String key, {String? owner}) {
    final value = this[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    _fail(key, 'int', owner: owner);
  }

  int? intOrNull(String key) {
    final value = this[key];
    if (value is int) return value;
    return value is num ? value.toInt() : null;
  }

  int intOr(String key, {int fallback = 0}) => intOrNull(key) ?? fallback;

  /// Reads a number upstream sends as either — `imdbMark` is `7` for some
  /// titles and `6.4` for others.
  double? doubleOrNull(String key) {
    final value = this[key];
    return value is num ? value.toDouble() : null;
  }

  /// An ISO-8601 timestamp, or nothing. Never throws.
  DateTime? dateTimeOrNull(String key) {
    final value = this[key];
    return value is String ? DateTime.tryParse(value) : null;
  }

  bool boolOr(String key, {bool fallback = false}) {
    final value = this[key];
    return value is bool ? value : fallback;
  }

  /// Parses an ISO-8601 timestamp, which is what every date in this API is.
  DateTime requireDateTime(String key, {String? owner}) {
    final value = this[key];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) _fail(key, 'an ISO-8601 timestamp', owner: owner);
    return parsed;
  }

  JsonMap? mapOrNull(String key) {
    final value = this[key];
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  /// Maps a JSON array of objects, skipping entries that are not objects.
  /// Empty when the field is absent or not a list.
  List<T> listOf<T>(String key, T Function(JsonMap json) parse) {
    final value = this[key];
    if (value is! List) return const [];
    return <T>[
      for (final item in value)
        if (item is Map) parse(item.cast<String, dynamic>()),
    ];
  }

  /// A `{"name": true}` object, skipping anything that is not a boolean.
  Map<String, bool> boolMap(String key) {
    final value = this[key];
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is bool) '${entry.key}': entry.value as bool,
    };
  }
}

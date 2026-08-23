import 'package:super_movies_api/super_movies_api.dart';

String contentTypeLabel(ContentType type) => switch (type) {
  ContentType.movie => 'Фільми',
  ContentType.serial => 'Серіали',
  ContentType.cartoonMovie => 'Мультфільми',
  ContentType.cartoonSeries => 'Мультсеріали',
  ContentType.anime => 'Аніме',
};

String providerLabel(String key) => switch (key) {
  'ashdi' => 'Ashdi',
  'tortuga' => 'Tortuga',
  'vidsrc' => 'VidSrc',
  _ => key,
};

String ratingLabel(double? mark) =>
    mark == null || mark == 0 ? '—' : mark.toStringAsFixed(1);

/// Joins the parts of a meta line, skipping the ones that are missing.
String metaLine(Iterable<String?> parts) =>
    parts.where((p) => p != null && p.isNotEmpty).join(' · ');

const _months = [
  'СІЧНЯ',
  'ЛЮТОГО',
  'БЕРЕЗНЯ',
  'КВІТНЯ',
  'ТРАВНЯ',
  'ЧЕРВНЯ',
  'ЛИПНЯ',
  'СЕРПНЯ',
  'ВЕРЕСНЯ',
  'ЖОВТНЯ',
  'ЛИСТОПАДА',
  'ГРУДНЯ',
];

const _weekdays = [
  'ПОНЕДІЛОК',
  'ВІВТОРОК',
  'СЕРЕДА',
  'ЧЕТВЕР',
  'ПʼЯТНИЦЯ',
  'СУБОТА',
  'НЕДІЛЯ',
];

/// `21:47` — the clock in the corner, and on the idle screen.
String clockLabel(DateTime now) =>
    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

/// `ЧЕТВЕР, 20 СЕРПНЯ`
String dateLabel(DateTime now) =>
    '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';

/// `0:56:12`, or `56:12` when it is under an hour.
String timecode(Duration position) {
  final hours = position.inHours;
  final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// `48,6 ГБ` — binary units, because that is what a filesystem reports.
///
/// A comma for the decimal mark: this is a Ukrainian interface, and `48.6`
/// reads as a thousands separator to half the people who see it.
String byteSize(int bytes) {
  if (bytes <= 0) return '0 Б';

  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  // Whole numbers past a gigabyte: nobody needs a tenth of a terabyte.
  final digits = unit <= 1 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
}

/// `Серія 4` on its own, or `4 · Політ` when the episode has a real title.
///
/// Plenty of episodes are named literally "Серія 4", and repeating that twice
/// in one chip is noise.
String episodeLabel(int number, String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'Серія $number';
  if (trimmed == 'Серія $number' || trimmed == '$number') {
    return 'Серія $number';
  }
  return '$number · $trimmed';
}

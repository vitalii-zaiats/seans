import 'package:super_movies_api/super_movies_api.dart';

/// The rows the home screen can show, in the order they appear.
///
/// Named so they can be switched off in settings and remembered by id. Storing
/// which are *hidden* rather than which are shown means a row added in a later
/// version turns up for everybody instead of staying invisible until somebody
/// goes looking for it.
enum HomeRailId {
  resume('resume', 'Продовжити дивитись'),
  apps('apps', 'Застосунки'),
  tv('tv', 'ТБ'),
  trending('trending', 'У тренді'),
  myList('myList', 'Мій список'),
  movies('movies', 'Фільми', ContentType.movie),
  serials('serials', 'Серіали', ContentType.serial),
  cartoonMovies('cartoonMovies', 'Мультфільми', ContentType.cartoonMovie),
  cartoonSeries('cartoonSeries', 'Мультсеріали', ContentType.cartoonSeries),
  anime('anime', 'Аніме', ContentType.anime);

  const HomeRailId(this.id, this.title, [this.type]);

  final String id;
  final String title;

  /// The catalogue section this row is a page of, where it is one. A hidden
  /// row with a type is a request the home screen simply never makes.
  final ContentType? type;

  static HomeRailId? tryParse(String? id) {
    for (final rail in values) {
      if (rail.id == id) return rail;
    }
    return null;
  }
}

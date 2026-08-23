import 'dart:async';
import 'dart:io';

import 'package:ashdi_finder/ashdi_finder.dart';
import 'package:super_movies_api/super_movies_api.dart';

/// Why one particular voice-over would not open.
///
/// Named down to the cause on purpose. "Nothing works" on a box has three
/// completely different reasons behind it — the certificate, the name lookup,
/// and the connection itself — and they need three different things done about
/// them. One message covering all three sent this codebase looking in the
/// wrong place for an evening.
String describeAshdiFailure(AshdiException error) {
  final cause = error.cause;
  if (cause == null) return error.message;

  if (cause is HandshakeException) {
    // The box's trust store or its clock. Both look identical from here, and
    // the clock is the one somebody can fix in a minute.
    return 'приставка не прийняла сертифікат ashdi.vip — перевірте дату й час '
        'у налаштуваннях боксу';
  }

  if (cause is SocketException) {
    if (cause.message.contains('Failed host lookup')) {
      return 'ashdi.vip не розпізнається — DNS приставки його не знає або '
          'провайдер його блокує';
    }
    final os = cause.osError;
    return 'мережа не пустила до ashdi.vip'
        '${os == null ? '' : ' (${os.message})'}';
  }

  if (cause is TimeoutException) return 'ashdi.vip не відповів вчасно';

  return 'не вдалося зʼєднатися з ashdi.vip ($cause)';
}

/// Turns a failure into something worth putting on a television screen.
String describeError(Object error) {
  if (error is AshdiException) return 'Не вдалося отримати потік';
  if (error is! ApiException) return 'Щось пішло не так';

  return switch (error) {
    ApiHttpException(isNotFound: true) => 'Цього вже немає в каталозі',
    ApiHttpException(isRateLimited: true) =>
      'Забагато запитів. Спробуйте за хвилину',
    ApiHttpException(isServerError: true) => 'Сервіс тимчасово недоступний',
    ApiHttpException(:final statusCode) => 'Помилка сервера ($statusCode)',
    ApiNetworkException() => 'Немає зʼєднання з мережею',
    ApiSerializationException() => 'Несподівана відповідь сервера',
  };
}

import 'dart:math';

import 'package:super_movies_api/super_movies_api.dart';
import 'package:super_movies_remote/super_movies_remote.dart';
import 'package:test/test.dart';

const _quick = Duration(milliseconds: 1);

/// Jitter with the dice taken out, so a wait can be compared to a wait.
final class Fixed implements Random {
  const Fixed();

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => 0;
}

ApiHttpException refusal(int status) => ApiHttpException(
  statusCode: status,
  uri: Uri.parse('https://api.test/device/events'),
  detail: 'no',
);

void main() {
  group('transient', () {
    test('a refusal that will never get better is not retried', () {
      // A television reconnecting to a 401 every second until somebody notices
      // is the failure this exists to prevent.
      expect(transient(refusal(401)), isFalse);
      expect(transient(refusal(403)), isFalse);
      expect(transient(refusal(404)), isFalse);
    });

    test('anything that might get better is', () {
      expect(transient(refusal(500)), isTrue);
      expect(transient(refusal(502)), isTrue);
      expect(
        transient(ApiNetworkException(Uri.parse('https://api.test'), 'reset')),
        isTrue,
      );
      expect(transient(StateError('who knows')), isTrue);
    });
  });

  group('backoff', () {
    test('grows, and then stops growing', () {
      final fixed = Random(1);
      final waits = [
        for (var attempt = 0; attempt < 12; attempt++)
          backoff(
            attempt,
            first: const Duration(seconds: 1),
            ceiling: const Duration(seconds: 30),
            random: fixed,
          ).inMilliseconds,
      ];

      expect(waits.first, lessThan(2000));
      // The jitter is 70–130%, so the ceiling is a ceiling on the base.
      expect(waits.every((wait) => wait <= 30000 * 1.3), isTrue);
      expect(waits.last, greaterThan(20000));
    });

    test('the jitter actually varies', () {
      final waits = {
        for (var index = 0; index < 20; index++)
          backoff(3, random: Random(index)).inMilliseconds,
      };

      // Twenty boxes coming back at once must not all reconnect in the same
      // millisecond.
      expect(waits.length, greaterThan(5));
    });
  });

  group('reconnecting', () {
    test('opens again when a stream simply ends', () async {
      var opened = 0;
      final stream = reconnecting(
        () {
          opened++;
          return Stream.value(opened);
        },
        first: _quick,
        ceiling: _quick,
      );

      expect(await stream.take(3).toList(), [1, 2, 3]);
    });

    test('opens again after a transient failure', () async {
      var opened = 0;
      final stream = reconnecting(
        () {
          opened++;
          return opened < 3
              ? Stream<int>.error(refusal(503))
              : Stream.value(opened);
        },
        first: _quick,
        ceiling: _quick,
      );

      expect(await stream.first, 3);
    });

    test('gives up on a refusal that will not get better', () async {
      final stream = reconnecting(
        () => Stream<int>.error(refusal(401)),
        first: _quick,
        ceiling: _quick,
      );

      await expectLater(
        stream.first,
        throwsA(
          isA<ApiHttpException>().having(
            (error) => error.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('a working connection resets the wait', () async {
      final waits = <Duration>[];
      var opened = 0;
      final stream = reconnecting(
        () {
          opened++;
          // Fails twice, works, then fails again. The wait after the working
          // one must be a short one, not the fourth doubling.
          return switch (opened) {
            1 || 2 || 4 => Stream<int>.error(refusal(503)),
            _ => Stream.value(opened),
          };
        },
        first: const Duration(milliseconds: 4),
        ceiling: const Duration(seconds: 30),
        onRetry: (_, wait) => waits.add(wait),
        random: const Fixed(),
      );

      await stream.take(2).toList();

      expect(waits.length, greaterThanOrEqualTo(3));
      expect(waits[1], greaterThan(waits[0]));
      // Back to the first wait rather than carrying on doubling.
      expect(waits[2], waits[0]);
    });

    test('a listener that stops listening stops the reconnecting', () async {
      var opened = 0;
      final subscription = reconnecting(
        () {
          opened++;
          return Stream.value(opened);
        },
        first: const Duration(milliseconds: 5),
        ceiling: const Duration(milliseconds: 5),
        random: const Fixed(),
      ).listen(null);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();
      // A generator sitting in its backoff finishes that wait and may open once
      // more before the cancellation reaches its next `yield`; what must not
      // happen is that it keeps going forever.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final settled = opened;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(opened, settled);
      expect(settled, greaterThan(1));
    });
  });
}

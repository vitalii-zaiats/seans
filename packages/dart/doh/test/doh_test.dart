import 'package:doh/doh.dart';
import 'package:test/test.dart';

/// A resolver that answers from a table and remembers what it was asked.
class FakeDoh {
  FakeDoh(this.answers);

  /// Keyed by host.
  final Map<String, String> answers;
  final List<Uri> asked = [];

  /// Hosts that make the fetch throw, as an unreachable resolver does.
  final Set<String> dead = {};

  Future<String> call(Uri url) async {
    asked.add(url);
    final host = url.queryParameters['name'] ?? '';
    if (dead.contains(url.host)) throw StateError('unreachable');
    return answers[host] ?? '{"Status":3}';
  }
}

String reply(List<(String data, int ttl)> records, {int status = 0}) {
  final answers = [
    for (final (data, ttl) in records)
      '{"name":"x","type":1,"TTL":$ttl,"data":"$data"}',
  ].join(',');
  return '{"Status":$status,"Answer":[$answers]}';
}

void main() {
  test('asks the first resolver by address, not by name', () async {
    final doh = FakeDoh({
      'ashdi.vip': reply([('82.221.131.119', 300)]),
    });
    final resolver = DohResolver(fetch: doh.call);

    await resolver.resolve('ashdi.vip');

    expect(doh.asked.single.host, '1.1.1.1');
    expect(
      doh.asked.single.queryParameters['name'],
      'ashdi.vip',
      reason: 'a resolver whose own name needs resolving is no use here',
    );
  });

  test('reads the addresses out', () async {
    final doh = FakeDoh({
      'ashdi.vip': reply([('82.221.131.119', 300), ('82.221.131.120', 300)]),
    });

    expect(await DohResolver(fetch: doh.call).resolve('ashdi.vip'), [
      '82.221.131.119',
      '82.221.131.120',
    ]);
  });

  test('a CNAME in the reply is not an address', () async {
    final doh = FakeDoh({
      'ashdi.vip':
          '{"Status":0,"Answer":['
          '{"name":"ashdi.vip","type":5,"TTL":300,"data":"edge.example."},'
          '{"name":"edge.example","type":1,"TTL":300,"data":"1.2.3.4"}]}',
    });

    expect(await DohResolver(fetch: doh.call).resolve('ashdi.vip'), [
      '1.2.3.4',
    ]);
  });

  test('nothing found is an empty list, so the caller can fall back', () async {
    final doh = FakeDoh(const {});

    expect(await DohResolver(fetch: doh.call).resolve('nope.test'), isEmpty);
  });

  test('a dead first resolver falls through to the second', () async {
    final doh = FakeDoh({
      'ashdi.vip': reply([('1.2.3.4', 300)]),
    })..dead.add('1.1.1.1');

    final found = await DohResolver(fetch: doh.call).resolve('ashdi.vip');

    expect(found, ['1.2.3.4']);
    expect(doh.asked.map((u) => u.host), ['1.1.1.1', '8.8.8.8']);
  });

  test('both dead is empty, not an exception', () async {
    final doh = FakeDoh(const {})..dead.addAll({'1.1.1.1', '8.8.8.8'});

    await expectLater(
      DohResolver(fetch: doh.call).resolve('ashdi.vip'),
      completion(isEmpty),
    );
  });

  test('a body that is not JSON is refused quietly', () async {
    final doh = FakeDoh({'ashdi.vip': '<html>blocked</html>'});

    expect(await DohResolver(fetch: doh.call).resolve('ashdi.vip'), isEmpty);
  });

  group('remembering', () {
    test('a second question inside the TTL asks nobody', () async {
      final doh = FakeDoh({
        'ashdi.vip': reply([('1.2.3.4', 300)]),
      });
      final resolver = DohResolver(fetch: doh.call);

      await resolver.resolve('ashdi.vip');
      await resolver.resolve('ashdi.vip');

      expect(doh.asked, hasLength(1));
    });

    test('and once it is past, it asks again', () async {
      var now = DateTime(2026);
      final doh = FakeDoh({
        'ashdi.vip': reply([('1.2.3.4', 60)]),
      });
      final resolver = DohResolver(fetch: doh.call, clock: () => now);

      await resolver.resolve('ashdi.vip');
      now = now.add(const Duration(seconds: 61));
      await resolver.resolve('ashdi.vip');

      expect(doh.asked, hasLength(2));
    });

    test('a TTL of seconds is held for longer than it says', () async {
      var now = DateTime(2026);
      final doh = FakeDoh({
        'ashdi.vip': reply([('1.2.3.4', 1)]),
      });
      final resolver = DohResolver(fetch: doh.call, clock: () => now);

      await resolver.resolve('ashdi.vip');
      now = now.add(const Duration(seconds: 5));
      await resolver.resolve('ashdi.vip');

      expect(
        doh.asked,
        hasLength(1),
        reason: 'a one-second TTL would mean a lookup per connection',
      );
    });

    test('a TTL of days is not held for days', () async {
      var now = DateTime(2026);
      final doh = FakeDoh({
        'ashdi.vip': reply([('1.2.3.4', 864000)]),
      });
      final resolver = DohResolver(fetch: doh.call, clock: () => now);

      await resolver.resolve('ashdi.vip');
      now = now.add(const Duration(hours: 2));
      await resolver.resolve('ashdi.vip');

      expect(doh.asked, hasLength(2));
    });

    test('the shortest TTL in the reply is the one that counts', () async {
      var now = DateTime(2026);
      final doh = FakeDoh({
        'ashdi.vip': reply([('1.2.3.4', 3600), ('1.2.3.5', 60)]),
      });
      final resolver = DohResolver(fetch: doh.call, clock: () => now);

      await resolver.resolve('ashdi.vip');
      now = now.add(const Duration(seconds: 61));
      await resolver.resolve('ashdi.vip');

      expect(doh.asked, hasLength(2));
    });

    test('forgetting one host asks again for it', () async {
      final doh = FakeDoh({
        'ashdi.vip': reply([('1.2.3.4', 300)]),
      });
      final resolver = DohResolver(fetch: doh.call);

      await resolver.resolve('ashdi.vip');
      resolver.forget('ashdi.vip');
      await resolver.resolve('ashdi.vip');

      expect(doh.asked, hasLength(2));
    });
  });

  test('a refusing resolver is tried past, not believed', () async {
    final doh = FakeDoh({'ashdi.vip': '{"Status":2}'});

    final found = await DohResolver(fetch: doh.call).resolve('ashdi.vip');

    expect(found, isEmpty);
    expect(
      doh.asked,
      hasLength(2),
      reason: 'SERVFAIL from one is a reason to ask the other',
    );
  });
}

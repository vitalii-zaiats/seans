import 'dart:async';

import 'package:super_movies_api/super_movies_api.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

void main() {
  group('start', () {
    test(
      'an anonymous launch sends no identifier and gets none back',
      () async {
        final transport = FakeTransport.json(startBody(anonymous: true));
        final api = apiFor(transport);

        final start = await api.start(
          const Launch.anonymous(platform: AppPlatform.web, version: '1.0.0'),
        );

        expect(transport.lastBody.containsKey('id'), isFalse);
        expect(transport.lastBody, {'platform': 'web', 'ver': '1.0.0'});
        expect(start.isAnonymous, isTrue);
        expect(start.install, isNull);
        expect(start.account, isNull);
        expect(start.session, isNull);
        expect(start.mode, AccountMode.anonymous);
        // The half that needs no row still arrives.
        expect(start.update.latest, '1.2.0');
        expect(start.serverTime.isUtc, isTrue);
      },
    );

    test('an identified launch sends everything and keeps the token', () async {
      final transport = FakeTransport.json(startBody());
      final api = apiFor(transport);

      final start = await api.start(
        const Launch.identified(
          installId: '3f2a1e40-9a1c-4f0e-8b1d-2c9e7a5b6d10',
          platform: AppPlatform.android,
          vendor: playStore,
          version: '1.0.0',
        ),
      );

      expect(transport.lastRequest.method, 'POST');
      expect(transport.lastRequest.url.path, '/init');
      expect(transport.lastBody, {
        'id': '3f2a1e40-9a1c-4f0e-8b1d-2c9e7a5b6d10',
        'platform': 'android',
        'vendor': 'com.android.vending',
        'ver': '1.0.0',
      });
      expect(start.mode, AccountMode.guest);
      expect(start.install!.isFirstRun, isTrue);
      expect(api.token, 'tok-1');
      expect(api.isSignedIn, isTrue);
    });

    test('a null token means the one we hold still works', () async {
      final transport = FakeTransport.json(startBody(token: null));
      final api = apiFor(transport, token: 'kept');

      await api.start(
        const Launch.identified(
          installId: 'x',
          platform: AppPlatform.linux,
          version: '1.0.0',
        ),
      );

      expect(api.token, 'kept');
    });

    test('the held token rides along in the header', () async {
      final transport = FakeTransport.json(startBody(token: null));
      final api = apiFor(transport, token: 'kept');

      await api.start(
        const Launch.identified(
          installId: 'x',
          platform: AppPlatform.linux,
          version: '1.0.0',
        ),
      );

      expect(transport.lastRequest.headers['Authorization'], 'Bearer kept');
    });

    test('no token means no Authorization header at all', () async {
      final transport = FakeTransport.json(startBody(anonymous: true));

      await apiFor(transport).start(
        const Launch.anonymous(platform: AppPlatform.web, version: '1.0.0'),
      );

      expect(
        transport.lastRequest.headers.containsKey('Authorization'),
        isFalse,
      );
    });
  });

  group('update plan', () {
    test('a required update is flagged for the caller to block on', () async {
      final transport = FakeTransport.json(
        startBody(action: 'required', channel: 'store'),
      );

      final start = await apiFor(transport).start(
        const Launch.anonymous(platform: AppPlatform.android, version: '0.1.0'),
      );

      expect(start.update.isRequired, isTrue);
      expect(start.update.isAvailable, isTrue);
      expect(start.update.updatesItself, isFalse);
      expect(start.update.url, contains('play.google.com'));
    });

    test('a sideloaded build is told to fetch it itself', () async {
      final transport = FakeTransport.json(
        startBody(action: 'optional', channel: 'self'),
      );

      final start = await apiFor(transport).start(
        const Launch.anonymous(platform: AppPlatform.android, version: '1.0.0'),
      );

      expect(start.update.updatesItself, isTrue);
      expect(start.update.action, UpdateAction.optional);
    });

    test('an action we do not know never blocks anybody', () async {
      final transport = FakeTransport.json(startBody(action: 'apocalypse'));

      final start = await apiFor(transport).start(
        const Launch.anonymous(platform: AppPlatform.web, version: '1.0.0'),
      );

      expect(start.update.action, UpdateAction.none);
      expect(start.update.isRequired, isFalse);
    });
  });

  group('features', () {
    test('a flag the server never mentioned is off', () async {
      final transport = FakeTransport.json(
        startBody(features: {'downloads': true, 'external_players': false}),
      );

      final start = await apiFor(transport).start(
        const Launch.anonymous(platform: AppPlatform.android, version: '1.0.0'),
      );

      expect(start.feature('downloads'), isTrue);
      expect(start.feature('external_players'), isFalse);
      expect(start.feature('never heard of it'), isFalse);
    });
  });

  group('identity', () {
    test('claiming rotates the token this client sends', () async {
      final transport = FakeTransport.json(identityBody(token: 'rotated'));
      final api = apiFor(transport, token: 'the guest token');

      final identity = await api.claim(
        email: 'vi@example.com',
        password: 'hunter2hunter2',
        displayName: 'Vitalii',
      );

      expect(transport.lastBody['display_name'], 'Vitalii');
      expect(identity.account.isGuest, isFalse);
      expect(identity.account.mode, AccountMode.claimed);
      // The whole point: the old token was revoked server-side, and a client
      // that kept it by hand would be signed out at the moment it gained an
      // account.
      expect(api.token, 'rotated');
    });

    test('display_name is omitted rather than sent as null', () async {
      final transport = FakeTransport.json(identityBody());

      await apiFor(transport)
          .register(email: 'vi@example.com', password: 'hunter2hunter2');

      expect(transport.lastBody.containsKey('display_name'), isFalse);
    });

    test('becoming a guest stores the token', () async {
      final transport = FakeTransport.json(identityBody(guest: true));
      final api = apiFor(transport);

      final identity = await api.becomeGuest();

      expect(identity.account.isGuest, isTrue);
      expect(identity.account.email, isNull);
      expect(api.token, 'tok-2');
    });

    test('signing out forgets the token here as well as there', () async {
      final transport = FakeTransport.empty();
      final api = apiFor(transport, token: 'live');

      await api.signOut();

      expect(transport.lastRequest.url.path, '/auth/logout');
      expect(api.token, isNull);
      expect(api.isSignedIn, isFalse);
    });

    test('forgetting the account leaves nothing behind', () async {
      final transport = FakeTransport.empty();
      final api = apiFor(transport, token: 'live');

      await api.forget();

      expect(transport.lastRequest.method, 'DELETE');
      expect(api.token, isNull);
    });

    test('onToken fires for every change and only for changes', () async {
      final seen = <String?>[];
      final api = apiFor(
        FakeTransport.json(identityBody(token: 'fresh')),
        token: 'old',
        onToken: seen.add,
      );

      await api.becomeGuest();
      api.token = 'fresh'; // same value — nothing to tell anybody

      expect(seen, ['fresh']);
    });
  });

  group('failures', () {
    test('a refusal carries the API detail, not a status line', () async {
      final transport = FakeTransport.json({
        'detail': 'vendor is only meaningful on android, not web',
      }, statusCode: 400);

      await expectLater(
        apiFor(transport).start(
          const Launch.anonymous(platform: AppPlatform.web, version: '1.0.0'),
        ),
        throwsA(
          isA<ApiHttpException>()
              .having((e) => e.isInvalid, 'isInvalid', isTrue)
              .having((e) => e.message, 'message', contains('vendor')),
        ),
      );
    });

    test('a stale token is an unauthorized, not a crash', () async {
      final transport = FakeTransport.json({
        'detail': 'this needs an account',
      }, statusCode: 401);

      await expectLater(
        apiFor(transport, token: 'stale').me(),
        throwsA(
          isA<ApiHttpException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('a taken email is a conflict', () async {
      final transport = FakeTransport.json({
        'detail': 'that email is taken',
      }, statusCode: 409);

      await expectLater(
        apiFor(transport).register(email: 'vi@example.com', password: 'x' * 14),
        throwsA(
          isA<ApiHttpException>().having(
            (e) => e.isConflict,
            'isConflict',
            isTrue,
          ),
        ),
      );
    });

    test('a schema rejection is flattened into one readable line', () async {
      final transport = FakeTransport.json({
        'detail': [
          {
            'loc': ['body', 'password'],
            'msg': 'String should have at least 8 characters',
          },
        ],
      }, statusCode: 422);

      await expectLater(
        apiFor(transport).register(email: 'vi@example.com', password: 'short'),
        throwsA(
          isA<ApiHttpException>().having(
            (e) => e.message,
            'message',
            'String should have at least 8 characters at body.password',
          ),
        ),
      );
    });

    test('a dead network is wrapped, not leaked', () async {
      final boom = StateError('connection reset');

      await expectLater(
        apiFor(FakeTransport.failing(boom)).me(),
        throwsA(
          isA<ApiNetworkException>().having((e) => e.cause, 'cause', boom),
        ),
      );
    });

    test('a body that is not JSON is a serialization failure', () async {
      final transport = FakeTransport(
        (_) async => ApiResponse.text(statusCode: 200, body: '<html>no</html>'),
      );

      await expectLater(
        apiFor(transport).me(),
        throwsA(isA<ApiSerializationException>()),
      );
    });

    test('a missing required field names itself', () async {
      final transport = FakeTransport.json({'id': 'abc'});

      await expectLater(
        apiFor(transport).me(),
        throwsA(
          isA<ApiSerializationException>().having(
            (e) => e.message,
            'message',
            contains('Account.display_name'),
          ),
        ),
      );
    });
  });

  deviceLinkTests();

  group('lifecycle', () {
    test('close closes the transport', () {
      final transport = FakeTransport.empty();
      apiFor(transport).close();

      expect(transport.closed, isTrue);
    });

    test('a trailing slash on the base url is ignored', () {
      final api = SuperMoviesApi(
        baseUrl: Uri.parse('https://api.test///'),
        transport: FakeTransport.empty(),
      );

      expect(api.uriFor('/init').toString(), 'https://api.test/init');
    });
  });
}

void deviceLinkTests() {
  group('device link', () {
    test('starting one hands back a code, a secret and where to go', () async {
      final transport = FakeTransport.json({
        'code': 'H7KQ2M',
        'secret': 'sec-1',
        'verify_path': '/link?code=H7KQ2M',
        'expires_in': 600,
      }, statusCode: 201);
      final api = apiFor(transport, token: 'tv');

      final link = await api.startDeviceLink();

      expect(transport.lastRequest.url.path, '/auth/device');
      expect(link.code, 'H7KQ2M');
      expect(
        link.verifyUrl(Uri.parse('https://app.test')).toString(),
        'https://app.test/link?code=H7KQ2M',
      );
      // Starting a pairing is not signing in: nothing was stored.
      expect(api.token, 'tv');
    });

    test('a box may name itself, and a blank name is not a name', () async {
      final transport = FakeTransport.json({
        'code': 'H7KQ2M',
        'secret': 'sec-1',
        'verify_path': '/r/H7KQ2M',
        'expires_in': 600,
      }, statusCode: 201);
      final api = apiFor(transport, token: 'tv');

      await api.startDeviceLink(deviceName: '  Android TV  ');
      expect(transport.lastBody, {'device_name': 'Android TV'});

      // Nothing to say is not the same as saying nothing: the key is left out
      // entirely, so the server falls back to the User-Agent as it always did.
      await api.startDeviceLink(deviceName: '   ');
      expect(transport.lastBody, isEmpty);

      await api.startDeviceLink();
      expect(transport.lastBody, isEmpty);
    });

    test('polling stops when it is told to, and not a request later', () async {
      // Nobody ever approves in this test — the poll would otherwise run to its
      // timeout, which is exactly what a pairing screen left open in a browser
      // used to do: `/auth/device/collect` every two seconds for ten minutes.
      final transport = FakeTransport.json({
        'status': 'pending',
        'identity': null,
      });
      final api = apiFor(transport, token: 'tv');
      final leave = Completer<void>();

      final polling = api.awaitDeviceLink(
        'sec-1',
        every: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 30),
        until: leave.future,
      );

      await Future<void>.delayed(const Duration(milliseconds: 90));
      final asked = transport.requests.length;
      expect(asked, greaterThan(1), reason: 'it should have been polling');

      leave.complete();
      expect(await polling, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      // At most the one that was already in flight when it was told. Without
      // the `until` this would have kept climbing for the whole timeout.
      expect(transport.requests.length, lessThanOrEqualTo(asked + 1));
    });

    test('pending is an answer, not an error', () async {
      final transport = FakeTransport.json({
        'status': 'pending',
        'identity': null,
      });
      final api = apiFor(transport, token: 'tv');

      expect(await api.collectDeviceLink('sec-1'), isNull);
      expect(api.token, 'tv');
    });

    test('collecting swaps this client onto the account', () async {
      final transport = FakeTransport.json({
        'status': 'linked',
        'identity': identityBody(token: 'linked-token'),
      });
      final api = apiFor(transport, token: 'the guest token');

      final identity = await api.collectDeviceLink('sec-1');

      expect(identity, isNotNull);
      expect(identity!.account.isGuest, isFalse);
      expect(api.token, 'linked-token');
    });

    test('the phone approves as itself', () async {
      final transport = FakeTransport.json({
        'code': 'H7KQ2M',
        'device_name': 'Android TV',
        'approved': true,
        'expires_in': 540,
      });

      final status = await apiFor(
        transport,
        token: 'phone',
      ).approveDeviceLink('H7KQ2M');

      expect(transport.lastRequest.url.path, '/auth/device/approve');
      expect(transport.lastBody, {'code': 'H7KQ2M'});
      expect(status.approved, isTrue);
      expect(status.deviceName, 'Android TV');
    });

    test('an expired status says so without arithmetic at the call site', () {
      const status = DeviceLinkStatus(
        code: 'H7KQ2M',
        approved: false,
        expiresIn: 0,
      );

      expect(status.hasExpired, isTrue);
    });
  });
}

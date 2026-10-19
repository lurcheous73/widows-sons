import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:widows_sons/chapter_state.dart';
import 'package:widows_sons/data.dart';

import 'support.dart';

void main() {
  test(
    'production URLs require HTTPS; debug HTTP is restricted to loopback',
    () {
      expect(
        () => AppConfig.validate('http://example.com'),
        throwsArgumentError,
      );
      expect(
        () => AppConfig.validate('https://user:secret@example.com'),
        throwsArgumentError,
      );
      expect(
        () => AppConfig.validate('https://example.com/?token=secret'),
        throwsArgumentError,
      );
      expect(AppConfig.validate('https://wsmba.the-grange.uk').scheme, 'https');
      expect(AppConfig.validate('http://127.0.0.1:19820').host, '127.0.0.1');
    },
  );

  test(
    'failed network keeps public offline cache but hides member verification',
    () async {
      final store = MemoryStorage()
        ..feed = jsonEncode(fixtureFeed())
        ..token = 'existing-secret';
      final state = ChapterState(
        ChapterApi(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
        store,
      );
      await state.initialize();
      expect(state.feed!.news.first['title'], 'A new home for chapter news.');
      expect(state.offline, isTrue);
      expect(state.signedIn, isTrue);
      expect(state.verified, isFalse);
      expect(await state.respond('cms-42', 'going'), isNotNull);
      state.dispose();
    },
  );

  test('expired session removes token from secure storage', () async {
    final store = MemoryStorage()..token = 'expired';
    final state = ChapterState(
      ChapterApi(
        client: MockClient(
          (r) async => r.url.path.endsWith('/feed')
              ? jsonResponse(fixtureFeed())
              : jsonResponse({'detail': 'Sign-in ended'}, 401),
        ),
      ),
      store,
    );
    await state.initialize();
    expect(state.signedIn, isFalse);
    expect(state.verified, isFalse);
    expect(store.token, isNull);
    state.dispose();
  });

  test(
    'activation stores secrets securely and never in public cache or URL',
    () async {
      final requests = <http.Request>[];
      final store = MemoryStorage();
      final state = ChapterState(
        ChapterApi(
          client: MockClient((r) async {
            requests.add(r);
            if (r.url.path.endsWith('/activate')) {
              return jsonResponse({'token': 'new-secret'});
            }
            if (r.url.path.endsWith('/me')) {
              return jsonResponse(fixtureMember());
            }
            return jsonResponse(fixtureFeed());
          }),
        ),
        store,
      );
      await state.initialize();
      await state.activate('wsi_test-invitation');
      expect(state.verified, isTrue);
      expect(store.token, 'new-secret');
      expect(store.feed, isNot(contains('new-secret')));
      expect(store.feed, isNot(contains('Test Member')));
      expect(requests.every((r) => r.url.query.isEmpty), isTrue);
      expect(requests.first.headers['Authorization'], isNull);
      expect(requests.last.headers['Authorization'], 'Bearer new-secret');
      expect(requests[1].followRedirects, isFalse);
      state.dispose();
    },
  );

  test(
    'secure storage failure revokes the newly issued server session',
    () async {
      final store = MemoryStorage()..failSecureWrite = true;
      var revoked = false;
      final state = ChapterState(
        ChapterApi(
          client: MockClient((r) async {
            if (r.method == 'DELETE') {
              revoked = true;
              return http.Response('', 204);
            }
            return jsonResponse({'token': 'unsaved'});
          }),
        ),
        store,
      );
      await state.activate('invite');
      expect(state.signedIn, isFalse);
      expect(store.token, isNull);
      expect(revoked, isTrue);
      expect(state.memberError, contains('secure sign-in'));
      state.dispose();
    },
  );

  test('failed RSVP never changes the displayed response', () async {
    final store = MemoryStorage()..token = 'valid';
    final state = ChapterState(
      ChapterApi(
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            return jsonResponse({'detail': 'Event removed'}, 404);
          }
          if (r.url.path.endsWith('/me')) {
            return jsonResponse(fixtureMember(rsvps: {'cms-42': 'interested'}));
          }
          return jsonResponse(fixtureFeed(events: true));
        }),
      ),
      store,
    );
    await state.initialize();
    expect(await state.respond('cms-42', 'going'), 'Event removed');
    expect(state.member!['rsvps']['cms-42'], 'interested');
    state.dispose();
  });

  test(
    'successful RSVP updates own response after server confirmation',
    () async {
      final store = MemoryStorage()..token = 'valid';
      final state = ChapterState(
        ChapterApi(
          client: MockClient((r) async {
            if (r.method == 'PUT') {
              expect(r.headers['Authorization'], 'Bearer valid');
              expect(jsonDecode(r.body), {'response': 'going'});
              return jsonResponse({'event_id': 'cms-42', 'response': 'going'});
            }
            if (r.url.path.endsWith('/me')) {
              return jsonResponse(fixtureMember());
            }
            return jsonResponse(fixtureFeed(events: true));
          }),
        ),
        store,
      );
      await state.initialize();
      expect(await state.respond('cms-42', 'going'), isNull);
      expect(state.member!['rsvps']['cms-42'], 'going');
      state.dispose();
    },
  );

  test('sign out clears an already expired server session', () async {
    final store = MemoryStorage()..token = 'valid';
    final state = ChapterState(
      ChapterApi(
        client: MockClient((r) async {
          if (r.method == 'DELETE') {
            return jsonResponse({'detail': 'Session expired'}, 401);
          }
          if (r.url.path.endsWith('/me')) return jsonResponse(fixtureMember());
          return jsonResponse(fixtureFeed());
        }),
      ),
      store,
    );
    await state.initialize();
    expect(await state.signOut(), isNull);
    expect(state.signedIn, isFalse);
    expect(state.member, isNull);
    expect(store.token, isNull);
    state.dispose();
  });

  test('a late member response cannot restore a signed-out card', () async {
    final store = MemoryStorage()..token = 'valid';
    final delayed = Completer<http.Response>();
    var delay = false;
    final state = ChapterState(
      ChapterApi(
        client: MockClient((r) async {
          if (r.method == 'DELETE') return http.Response('', 204);
          if (r.url.path.endsWith('/me')) {
            return delay ? delayed.future : jsonResponse(fixtureMember());
          }
          return jsonResponse(fixtureFeed());
        }),
      ),
      store,
    );
    await state.initialize();
    delay = true;
    final refresh = state.refreshMember();
    await state.signOut();
    delayed.complete(jsonResponse(fixtureMember()));
    await refresh;
    expect(state.member, isNull);
    expect(state.signedIn, isFalse);
    state.dispose();
  });
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:widows_sons/data.dart';
import 'package:widows_sons/chapter_state.dart';

Map<String, dynamic> fixtureFeed({bool events = false}) => {
  'chapter': {
    'slug': 'lr',
    'name': 'Leicestershire & Rutland Widows Sons',
    'display_name': 'Widows Sons L&R',
    'theme': {'accent': '#c5a365'},
  },
  'news': [
    {
      'id': '11',
      'title': 'A new home for chapter news.',
      'excerpt': 'Published chapter news.',
      'body': 'Welcome to the chapter.\n\nAnother paragraph.',
      'published_at': '2026-10-19T11:44:25Z',
      'url': 'https://wsmba.the-grange.uk/news/',
    },
  ],
  'events': events
      ? [
          {
            'id': 'cms-42',
            'title': 'Test chapter ride',
            'starts_at': '2099-07-01T10:00:00+01:00',
            'location': 'Test meeting point',
            'description': 'Test route details',
            'url': 'https://wsmba.the-grange.uk/event/',
          },
        ]
      : [],
  'pages': [
    {
      'slug': 'about',
      'title': 'A shared road ahead.',
      'body': 'Motorcycling and friendship.',
      'url': 'https://wsmba.the-grange.uk/about/',
    },
  ],
  'updated_at': '2026-10-19T12:00:00Z',
};

Map<String, dynamic> fixtureMember({Map<String, String> rsvps = const {}}) => {
  'id': '7da8e118-dd70-439b-bc0d-34ef4645de77',
  'display_name': 'Test Member',
  'membership_type': 'member',
  'status': 'active',
  'chapter': 'Widows Sons L&R',
  'verified_at': '2026-10-19T12:01:00Z',
  'rsvps': rsvps,
};

class MemoryStorage implements ChapterStorage {
  String? feed;
  String? token;
  bool failSecureWrite = false;
  @override
  Future<String?> readFeed() async => feed;
  @override
  Future<void> writeFeed(String value) async {
    feed = value;
  }

  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String value) async {
    if (failSecureWrite) throw StateError('Keychain unavailable');
    token = value;
  }

  @override
  Future<void> deleteToken() async {
    token = null;
  }
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

ChapterState fixtureState({bool member = false, bool events = false}) {
  final state = ChapterState(
    ChapterApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/feed')) {
          return jsonResponse(fixtureFeed(events: events));
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse(fixtureMember());
        }
        return jsonResponse({});
      }),
    ),
    MemoryStorage(),
  );
  state.feed = ChapterFeed(fixtureFeed(events: events));
  state.member = member ? fixtureMember() : null;
  state.loading = false;
  return state;
}

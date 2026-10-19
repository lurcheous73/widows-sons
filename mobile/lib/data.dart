import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'WIDOWS_SONS_BASE_URL',
    defaultValue: 'https://wsmba.the-grange.uk',
  );
  static const chapter = String.fromEnvironment(
    'WIDOWS_SONS_CHAPTER',
    defaultValue: 'lr',
  );

  static Uri validate(String value) {
    final uri = Uri.parse(value);
    final local =
        kDebugMode && ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host);
    if (uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.host.isEmpty ||
        !['', '/'].contains(uri.path) ||
        !(uri.scheme == 'https' || (uri.scheme == 'http' && local))) {
      throw ArgumentError('Use HTTPS, or a loopback URL for a debug build.');
    }
    return uri;
  }
}

class ChapterFeed {
  final Map<String, dynamic> json;
  ChapterFeed(this.json) {
    if (json['chapter'] is! Map ||
        json['news'] is! List ||
        json['events'] is! List) {
      throw const FormatException('Invalid chapter feed');
    }
  }
  Map<String, dynamic> get chapter =>
      Map<String, dynamic>.from(json['chapter']);
  String get name => chapter['display_name'] as String;
  List<Map<String, dynamic>> get news =>
      (json['news'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
  List<Map<String, dynamic>> get events => (json['events'] as List)
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  List<Map<String, dynamic>> get pages => (json['pages'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  DateTime get updatedAt => DateTime.parse(json['updated_at']);
}

class ApiFailure implements Exception {
  final String message;
  final int? status;
  const ApiFailure(this.message, [this.status]);
  @override
  String toString() => message;
}

class ChapterApi {
  final http.Client client;
  final Uri base;
  final String slug;
  ChapterApi({
    http.Client? client,
    String baseUrl = AppConfig.baseUrl,
    this.slug = AppConfig.chapter,
  }) : client = client ?? http.Client(),
       base = AppConfig.validate(baseUrl);

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    String? token,
    Map<String, dynamic>? body,
  }) async {
    try {
      final req = http.Request(
        method,
        base.resolve('/api/v1/mobile/${Uri.encodeComponent(slug)}/$path'),
      );
      // Never put invitations or session tokens in URLs or log messages.
      req.headers['Accept'] = 'application/json';
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      req.followRedirects = false;
      final response = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      Map<String, dynamic> data = {};
      if (response.body.isNotEmpty) {
        try {
          data = Map<String, dynamic>.from(jsonDecode(response.body));
        } on FormatException {
          /* Error pages are not JSON. */
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data['detail'];
        throw ApiFailure(
          detail is String ? detail : 'The chapter server could not complete this request. Try again.',
          response.statusCode,
        );
      }
      return data;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'Unable to reach the chapter. Check your connection and try again.',
      );
    }
  }

  Future<ChapterFeed> feed() async => ChapterFeed(await request('feed'));
  Future<String> activate(String code) async =>
      (await request('activate', method: 'POST', body: {'code': code}))['token']
          as String;
  Future<Map<String, dynamic>> me(String token) => request('me', token: token);
  Future<void> signOut(String token) async {
    await request('session', method: 'DELETE', token: token);
  }

  Future<void> rsvp(String token, String id, String response) async {
    await request(
      'events/${Uri.encodeComponent(id)}/rsvp',
      method: 'PUT',
      token: token,
      body: {'response': response},
    );
  }

  void close() => client.close();
}

abstract class ChapterStorage {
  Future<String?> readFeed();
  Future<void> writeFeed(String value);
  Future<String?> readToken();
  Future<void> writeToken(String value);
  Future<void> deleteToken();
}

class DeviceStorage implements ChapterStorage {
  final FlutterSecureStorage secure;
  final String namespace;
  DeviceStorage({
    this.secure = const FlutterSecureStorage(),
    String baseUrl = AppConfig.baseUrl,
    String slug = AppConfig.chapter,
  }) : namespace = 'widows_sons.$baseUrl.$slug.v1';
  @override
  Future<String?> readFeed() async => (await SharedPreferences.getInstance())
      .getString('$namespace.public_feed');
  @override
  Future<void> writeFeed(String value) async {
    await (await SharedPreferences.getInstance()).setString(
      '$namespace.public_feed',
      value,
    );
  }

  @override
  Future<String?> readToken() => secure.read(key: '$namespace.session');
  @override
  Future<void> writeToken(String value) =>
      secure.write(key: '$namespace.session', value: value);
  @override
  Future<void> deleteToken() => secure.delete(key: '$namespace.session');
}

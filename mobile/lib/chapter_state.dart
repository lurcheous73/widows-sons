import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data.dart';

class ChapterState extends ChangeNotifier {
  final ChapterApi api;
  final ChapterStorage storage;
  ChapterFeed? feed;
  Map<String, dynamic>? member;
  String? _token;
  String? feedError;
  String? memberError;
  bool loading = true;
  bool busy = false;
  bool offline = false;
  bool get signedIn => _token != null;
  bool get verified => member != null;
  ChapterState(this.api, this.storage);

  Future<void> initialize() async {
    try {
      final cached = await storage.readFeed();
      if (cached != null) {
        feed = ChapterFeed(Map<String, dynamic>.from(jsonDecode(cached)));
        offline = true;
        notifyListeners();
      }
    } catch (_) {
      /* A damaged public cache is replaced by the next successful fetch. */
    }
    try {
      _token = await storage.readToken();
    } catch (_) {
      memberError =
          'Secure storage is unavailable. Unlock your device and try again.';
    }
    await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    await Future.wait([refreshFeed(), if (signedIn) refreshMember()]);
    loading = false;
    notifyListeners();
  }

  Future<void> refreshFeed() async {
    try {
      feed = await api.feed();
      offline = false;
      feedError = null;
      try {
        await storage.writeFeed(jsonEncode(feed!.json));
      } catch (_) {
        /* Reading online still works when cache is full. */
      }
    } catch (error) {
      offline = true;
      feedError = error is ApiFailure
          ? error.message
          : 'Chapter updates could not be read. Please try again.';
    }
    notifyListeners();
  }

  Future<void> refreshMember() async {
    if (_token == null) return;
    final token = _token!;
    try {
      final result = await api.me(token);
      if (_token != token) return;
      member = result;
      memberError = null;
    } on ApiFailure catch (error) {
      if (_token != token) return;
      member = null; // Never display cached membership as currently verified.
      memberError = error.message;
      if (error.status == 401) {
        _token = null;
        try {
          await storage.deleteToken();
        } catch (_) {
          /* Server already rejects the session. */
        }
      }
    }
    notifyListeners();
  }

  Future<void> activate(String code) async {
    if (busy) return;
    busy = true;
    memberError = null;
    notifyListeners();
    String? issued;
    try {
      issued = await api.activate(code.trim());
      try {
        await storage.writeToken(issued);
      } catch (_) {
        try {
          await api.signOut(issued);
        } catch (_) {
          /* Token is never retained by this client. */
        }
        throw const ApiFailure(
          'Your device could not save a secure sign-in. Unlock it and try again with a new invitation.',
        );
      }
      _token = issued;
      await refreshMember();
    } on ApiFailure catch (error) {
      memberError = error.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> respond(String id, String response) async {
    if (!verified || _token == null) {
      return 'Connect and sign in before sending an RSVP.';
    }
    if (busy) return null;
    busy = true;
    notifyListeners();
    try {
      await api.rsvp(_token!, id, response);
      if (member != null) {
        member = {
          ...member!,
          'rsvps': {
            ...Map<String, dynamic>.from(member!['rsvps']),
            id: response,
          },
        };
      }
      return null;
    } on ApiFailure catch (error) {
      if (error.status == 401) await refreshMember();
      return error.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> signOut() async {
    if (_token == null || busy) return null;
    busy = true;
    notifyListeners();
    try {
      try {
        await api.signOut(_token!);
      } on ApiFailure catch (error) {
        if (error.status != 401) rethrow;
      }
      member = null;
      await storage.deleteToken();
      _token = null;
      member = null;
      memberError = null;
      return null;
    } on ApiFailure catch (error) {
      return error.message;
    } catch (_) {
      return 'Your server session has ended. Secure storage could not be cleared; unlock your device and retry.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}

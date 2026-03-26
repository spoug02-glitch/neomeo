import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gCal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local_event.dart';

class CalendarService {
  static const _kLocalEvents = 'local_events_v2';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [gCal.CalendarApi.calendarEventsReadonlyScope],
  );

  GoogleSignInAccount? _currentUser;

  // ── Google auth ────────────────────────────────────────────
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() => _googleSignIn.disconnect();

  // ── Local event CRUD ───────────────────────────────────────
  Future<List<LocalEvent>> getAllLocalEvents() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kLocalEvents) ?? [];
    return list
        .map((s) => LocalEvent.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveEvent(LocalEvent event) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kLocalEvents) ?? [];
    list.add(jsonEncode(event.toJson()));
    await p.setStringList(_kLocalEvents, list);
  }

  Future<void> updateEvent(LocalEvent updated) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kLocalEvents) ?? [];
    final idx = list.indexWhere((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m['id'] == updated.id;
    });
    if (idx >= 0) {
      list[idx] = jsonEncode(updated.toJson());
      await p.setStringList(_kLocalEvents, list);
    }
  }

  Future<void> deleteEvent(String eventId) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kLocalEvents) ?? [];
    list.removeWhere((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m['id'] == eventId;
    });
    await p.setStringList(_kLocalEvents, list);
  }

  // ── Day-based local event query ────────────────────────────
  Future<List<LocalEvent>> getLocalEventsForDay(DateTime day) async {
    final events = await getAllLocalEvents();
    final result = events.where((e) => _isEventOnDay(e, day)).toList();
    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  bool _isEventOnDay(LocalEvent e, DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);

    if (d.isBefore(start)) return false;

    switch (e.repeatType) {
      case RepeatType.none:
        return _isSameDay(start, d);
      case RepeatType.daily:
        if (e.repeatExcludeWeekends && (d.weekday == 6 || d.weekday == 7)) {
          return false;
        }
        return true;
      case RepeatType.weeklyDays:
        // repeatDays: 0=일,1=월,...,6=토  vs  DateTime.weekday: 1=월,...,7=일
        final dow = d.weekday == 7 ? 0 : d.weekday;
        return e.repeatDays.contains(dow);
      case RepeatType.weekly:
        return e.startTime.weekday == d.weekday;
      case RepeatType.monthly:
        return e.startTime.day == d.day;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Google Calendar events for today ──────────────────────
  Future<List<gCal.Event>> getGoogleEventsToday() async {
    if (_currentUser == null) {
      _currentUser = await _googleSignIn.signInSilently();
    }
    if (_currentUser == null) return [];

    try {
      final auth.AuthClient? httpClient =
          await _googleSignIn.authenticatedClient();
      if (httpClient == null) return [];
      final calendar = gCal.CalendarApi(httpClient);
      final now = DateTime.now();
      final events = await calendar.events.list(
        'primary',
        timeMin: DateTime(now.year, now.month, now.day, 0, 0, 0).toUtc(),
        timeMax: DateTime(now.year, now.month, now.day, 23, 59, 59).toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );
      return events.items ?? [];
    } catch (_) {
      return [];
    }
  }
}

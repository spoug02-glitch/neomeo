import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:shared_preferences/shared_preferences.dart';

class CalendarService {
  static const _kLocalEvents = 'local_calendar_events';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [CalendarApi.calendarEventsReadonlyScope],
  );

  GoogleSignInAccount? _currentUser;

  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser;
    } catch (error) {
      return null;
    }
  }

  Future<void> signOut() => _googleSignIn.disconnect();

  Future<List<Event>> getTodayEvents() async {
    List<Event> allEvents = await _getLocalEvents();

    if (_currentUser == null) {
      _currentUser = await _googleSignIn.signInSilently();
    }

    if (_currentUser != null) {
      try {
        final auth.AuthClient? httpClient = await _googleSignIn.authenticatedClient();
        if (httpClient != null) {
          final calendar = CalendarApi(httpClient);
          final now = DateTime.now();

          final events = await calendar.events.list(
            'primary',
            timeMin: DateTime(now.year, now.month, now.day, 0, 0, 0).toUtc(),
            timeMax: DateTime(now.year, now.month, now.day, 23, 59, 59).toUtc(),
            singleEvents: true,
            orderBy: 'startTime',
          );
          if (events.items != null) {
            allEvents.addAll(events.items!);
          }
        }
      } catch (e) {
        // Silently fail Google Sync, just return local events
      }
    }

    // Sort by start time
    allEvents.sort((a, b) {
      final aStart = a.start?.dateTime ?? a.start?.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bStart = b.start?.dateTime ?? b.start?.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aStart.compareTo(bStart);
    });

    return allEvents;
  }

  Future<List<Event>> _getLocalEvents() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kLocalEvents) ?? [];
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return list.map((s) => Event.fromJson(jsonDecode(s))).where((e) {
      final start = e.start?.dateTime ?? e.start?.date;
      if (start == null) return false;
      return start.isAfter(todayStart) && start.isBefore(todayEnd);
    }).toList();
  }

  Future<void> saveLocalEvent(String summary, DateTime startTime) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kLocalEvents) ?? [];
    
    final event = Event()
      ..summary = summary
      ..start = (EventDateTime()..dateTime = startTime)
      ..end = (EventDateTime()..dateTime = startTime.add(const Duration(hours: 1)));

    list.add(jsonEncode(event.toJson()));
    await p.setStringList(_kLocalEvents, list);
  }

  String classifyEvent(Event event) {
    final title = event.summary?.toLowerCase() ?? '';
    final description = event.description?.toLowerCase() ?? '';
    final fullText = '$title $description';

    if (fullText.contains('회의') || fullText.contains('미팅') ||
        fullText.contains('zoom') || fullText.contains('meeting')) return '회의';
    if (fullText.contains('약속') || fullText.contains('식사') ||
        fullText.contains('dinner') || fullText.contains('lunch')) return '약속';
    if (fullText.contains('출근') || fullText.contains('회사') ||
        fullText.contains('work')) return '출근';
    if (fullText.contains('운동') || fullText.contains('gym') ||
        fullText.contains('요가') || fullText.contains('필라테스')) return '운동';

    return '기타';
  }
}

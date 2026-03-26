// lib/app/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/checklist/checklist_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/checklist_settings_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/outing_select/outing_select_screen.dart';
import '../features/checklist_list/checklist_list_screen.dart';
import '../data/prefs_service.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/checklist',
      builder: (_, state) {
        final outingType = state.uri.queryParameters['type'] ?? '출근';
        return ChecklistScreen(outingType: outingType);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/calendar',
      builder: (_, __) => const CalendarScreen(),
    ),
    GoRoute(
      path: '/outing-select',
      builder: (_, __) => const OutingSelectScreen(),
    ),
    GoRoute(
      path: '/list',
      builder: (_, __) => const ChecklistListScreen(),
    ),
    GoRoute(
      path: '/checklist-settings',
      builder: (_, state) {
        final placeId    = state.uri.queryParameters['placeId']    ?? '';
        final outingType = state.uri.queryParameters['type']       ?? '외출';
        return ChecklistSettingsScreen(placeId: placeId, outingType: outingType);
      },
    ),
  ],
  redirect: (context, state) async {
    final onboardingDone = await PrefsService.isOnboardingDone();
    final loggingIn = state.matchedLocation == '/onboarding';

    if (!onboardingDone) {
      return loggingIn ? null : '/onboarding';
    }

    if (loggingIn) {
      return '/home';
    }

    return null;
  },
);

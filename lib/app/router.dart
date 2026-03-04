// lib/app/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/checklist/checklist_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/calendar/calendar_screen.dart';
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

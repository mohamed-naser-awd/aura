import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/call_log/call_log_screen.dart';
import '../features/contacts/contacts_screen.dart';
import '../features/dialer/dialer_screen.dart';
import '../features/groups/create_group_screen.dart';
import '../features/groups/group_detail_screen.dart';
import '../features/groups/groups_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/settings_screen.dart';
import 'home_shell.dart';
import 'providers.dart';

/// Route paths used across the app.
class Routes {
  static const onboarding = '/onboarding';
  static const dialer = '/dialer';
  static const callLog = '/call-log';
  static const contacts = '/contacts';
  static const groups = '/groups';
  static const settings = '/settings';
  static const groupCreate = '/groups/new';
  static const groupDetail = '/groups/:id';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.dialer,
    redirect: (context, state) {
      // Onboarding gate: if Aura is not the default dialer, force onboarding.
      final isDefault = ref.read(isDefaultDialerProvider).valueOrNull ?? true;
      final goingToOnboarding = state.matchedLocation == Routes.onboarding;
      if (!isDefault && !goingToOnboarding) return Routes.onboarding;
      if (isDefault && goingToOnboarding) return Routes.dialer;
      return null;
    },
    routes: [
      GoRoute(path: Routes.onboarding, builder: (_, __) => const OnboardingScreen()),
      // '/groups/new' must precede '/groups/:id' so "new" isn't parsed as an id.
      GoRoute(path: Routes.groupCreate, builder: (_, __) => const CreateGroupScreen()),
      GoRoute(
        path: Routes.groupDetail,
        builder: (_, state) => GroupDetailScreen(groupId: int.parse(state.pathParameters['id']!)),
      ),
      // Bottom-nav shell hosting the primary tabs.
      ShellRoute(
        builder: (_, __, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: Routes.dialer, builder: (_, __) => const DialerScreen()),
          GoRoute(path: Routes.callLog, builder: (_, __) => const CallLogScreen()),
          GoRoute(path: Routes.contacts, builder: (_, __) => const ContactsScreen()),
          GoRoute(path: Routes.groups, builder: (_, __) => const GroupsScreen()),
          GoRoute(path: Routes.settings, builder: (_, __) => const SettingsScreen()),
        ],
      ),
    ],
  );
});

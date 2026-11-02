import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/organizer/organizer_page.dart';
import '../features/organizer/connections/connections_page.dart';
import '../features/organizer/history/history_page.dart';
import '../features/organizer/organizer_state.dart';
import '../features/organizer/ai/ai_usage_page.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/organize',
    routes: [
      GoRoute(path: '/settings', redirect: (_, _) => '/connections'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/organize',
                pageBuilder: (_, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const OrganizerPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'assistant',
                    redirect: (_, _) =>
                        ref.read(organizerProvider).directory.isEmpty
                        ? '/organize'
                        : null,
                    pageBuilder: (_, state) => NoTransitionPage<void>(
                      key: state.pageKey,
                      child: const OrganizerPage(step: OrganizerStep.assistant),
                    ),
                    routes: [
                      GoRoute(
                        path: 'preview',
                        pageBuilder: (_, state) => NoTransitionPage<void>(
                          key: state.pageKey,
                          child: const OrganizerPage(
                            step: OrganizerStep.preview,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ai-usage',
                builder: (_, _) => const AiUsagePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/connections',
                builder: (_, _) => const ConnectionsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

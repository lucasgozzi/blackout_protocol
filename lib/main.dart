import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/engine/game_context.dart';
import 'core/engine/game_session_notifier.dart';
import 'core/models/game_state.dart';
import 'data/providers.dart';
import 'features/dev_launcher/dev_launcher_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/campaign_select/campaign_select_screen.dart';
import 'features/mission_select/mission_select_screen.dart';
import 'features/operator_select/operator_select_screen.dart';
import 'features/game_board/game_board_screen.dart';
import 'features/result/result_screen.dart';

void main() {
  runApp(const ProviderScope(child: BlackoutApp()));
}

class BlackoutApp extends ConsumerWidget {
  const BlackoutApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = _buildRouter(ref);
    return MaterialApp.router(
      title: 'Blackout Protocol',
      debugShowCheckedModeBanner: kDebugMode,
      theme: _buildTheme(),
      routerConfig: router,
    );
  }

  GoRouter _buildRouter(WidgetRef ref) {
    return GoRouter(
      initialLocation: '/splash',
      routes: [
        // DevLauncher desativado — usar /dev para reativar
        // GoRoute(
        //   path: '/dev',
        //   builder: (context, _) => DevLauncherScreen(
        //     onLaunch: (ctx) => _launchContext(ctx, context, ref),
        //   ),
        // ),
        GoRoute(
          path: '/splash',
          builder: (_, __) => const SplashScreen(),
        ),
        GoRoute(
          path: '/campaigns',
          builder: (_, __) => const CampaignSelectScreen(),
        ),
        GoRoute(
          path: '/campaigns/:campaignId/missions',
          builder: (_, state) => MissionSelectScreen(
            campaignId: state.pathParameters['campaignId']!,
          ),
        ),
        GoRoute(
          path: '/campaigns/:campaignId/missions/:missionId/operators',
          builder: (_, state) => OperatorSelectScreen(
            campaignId: state.pathParameters['campaignId']!,
            missionId: state.pathParameters['missionId']!,
          ),
        ),
        GoRoute(
          path: '/game',
          builder: (_, __) => const GameBoardScreen(),
        ),
        GoRoute(
          path: '/result',
          builder: (_, __) => const ResultScreen(),
        ),
      ],
    );
  }

  Future<void> _launchContext(GameContext ctx, BuildContext context, WidgetRef ref) async {
    final enemyCatalog = await ref.read(enemyCatalogProvider.future);
    final repo = await ref.read(campaignRepositoryProvider.future);
    final mission = repo.getMissionById(ctx.missionId);

    final notifier = ref.read(gameSessionProvider.notifier);
    notifier.init(enemyCatalog);
    notifier.loadContext(ctx, mission);

    if (context.mounted) context.go('/game');
  }

  ThemeData _buildTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF050510),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00FF88),
        secondary: Color(0xFF00AAFF),
        error: Color(0xFFFF4444),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D0D1A),
        elevation: 0,
      ),
    );
  }
}

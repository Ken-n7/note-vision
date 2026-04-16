import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/editor/presentation/editor_shell_screen.dart';
import 'features/landing/presentation/landing_screen.dart';
import 'features/profile/presentation/profile_stats_screen.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note Vision',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      onGenerateRoute: (settings) {
        if (settings.name == EditorShellScreen.routeName) {
          final args = settings.arguments! as EditorShellArgs;
          return MaterialPageRoute(
            builder: (_) => EditorShellScreen(args: args),
          );
        }
        if (settings.name == ProfileStatsScreen.routeName) {
          return MaterialPageRoute(
            builder: (_) => const ProfileStatsScreen(),
          );
        }
        return null;
      },
      home: const LandingScreen(),
    );
  }
}
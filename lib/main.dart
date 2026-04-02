import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/user_profile_service.dart';
import 'features/collection/presentation/collection_screen.dart';
import 'features/editor/presentation/editor_shell_screen.dart';
import 'features/landing/presentation/landing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ← required for SharedPreferences
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
        return null;
      },
      home: FutureBuilder<bool>(
        future: UserProfileService.isOnboardingComplete(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              backgroundColor: Color(0xFF0F0F0F),
              body: SizedBox.shrink(), // blank screen while checking
            );
          }
          return snapshot.data!
              ? const CollectionScreen()
              : const LandingScreen(); // ← goes to onboarding if not done
        },
      ),
    );
  }
}
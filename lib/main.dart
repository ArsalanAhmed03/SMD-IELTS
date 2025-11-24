import 'package:flutter/material.dart';
import 'core/app_state.dart';
import 'core/app_theme.dart';
import 'core/supabase_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'mock/mock_data.dart';
import 'screens/premium/premium_screen.dart';
import 'screens/shell/app_shell.dart';
import 'screens/skill/practice_set_screen.dart';
import 'screens/skill/question_player_screen.dart';
import 'screens/skill/practice_summary_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var supaUrl = 'https://bsltfusozfyfqyfhjmfq.supabase.co';
  var supaAnon = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzbHRmdXNvemZ5ZnF5ZmhqbWZxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI1MTI3MTEsImV4cCI6MjA3ODA4ODcxMX0.VmStaum1KZkKgKXyFni3dX6uM9bMfm_d-o8jGoA1vug';
  try {
    await dotenv.load(fileName: '.env');
    supaUrl = dotenv.env['SUPABASE_URL'] ?? supaUrl;
    supaAnon = dotenv.env['SUPABASE_ANON_KEY'] ?? supaAnon;
  } catch (_) {
    // If dotenv fails to load, keep defaults above.
  }
  await Supa.init(url: supaUrl, anonKey: supaAnon);
  runApp(const IeltsApp());
}

class IeltsApp extends StatelessWidget {
  const IeltsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState(seedResults: recentResults);
    return AppStateScope(
      notifier: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'IELTS Prep',
        theme: buildAppTheme(),
        themeMode: ThemeMode.light, // force light while designing
        initialRoute: '/splash',
        routes: {
          '/splash': (_) => const SplashScreen(),
          '/onboarding': (_) => const OnboardingScreen(),
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/shell': (_) => const AppShell(),
          '/premium': (_) => const PremiumScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/practiceSet') {
            final id = settings.arguments as String;
            return MaterialPageRoute(builder: (_) => PracticeSetScreen(practiceSetId: id));
          }
          if (settings.name == '/questionPlayer') {
            final id = settings.arguments as String;
            return MaterialPageRoute(builder: (_) => QuestionPlayerScreen(practiceSetId: id));
          }
          if (settings.name == '/practiceSummary') {
            return MaterialPageRoute(
              builder: (_) => const PracticeSummaryScreen(),
              settings: settings,
            );
          }
          return null;
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'services/database_service.dart';
import 'services/auth_service.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';
import 'config/app_config.dart';
import 'ui/common/app_theme.dart';

void main() async {
  // Ensure Flutter is properly initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // For web, add a small delay to ensure proper initialization
  if (kIsWeb) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  
  // Initialize services
  final db = DatabaseService();
  await db.init();
  final authService = AuthService();
  
  try {
    await authService.initFirebase();
  } catch (e) {
    // Firebase not configured; proceed without remote auth (Google sign-in may fail)
    debugPrint('Firebase init skipped: $e');
  }
  
  // Debug backend URL
  // ignore: avoid_print
  print('Hi-Doc backend URL: ${AppConfig.backendBaseUrl}');
  
  runApp(HiDocApp(db: db, authService: authService));
}

class HiDocApp extends StatelessWidget {
  final DatabaseService db;
  final AuthService authService;
  const HiDocApp({super.key, required this.db, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: db),
        ChangeNotifierProvider(create: (_) => AuthProvider(authService)),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider(db: db)),
      ],
      child: Builder(builder: (context) {
        // Attach settings to chat provider (once)
        final settings = context.read<SettingsProvider>();
        final chat = context.read<ChatProvider>();
        chat.attachSettings(settings);
        
        // Load existing messages from database
        chat.loadMessages();
        
        return Consumer<AuthProvider>(
          builder: (context, auth, _) => MaterialApp(
            title: 'Hi-Doc',
            theme: AppTheme.light,
            builder: (context, child) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.5, -0.6),
                    radius: 1.2,
                    colors: [
                      Color(0xFFE8F3FF),
                      Colors.white,
                    ],
                    stops: [0, 0.65],
                  ),
                ),
                child: child,
              );
            },
            home: (kIsWeb || auth.user != null)
                ? const HomeShell()
                : const LoginScreen(),
          ),
        );
      }),
    );
  }
}

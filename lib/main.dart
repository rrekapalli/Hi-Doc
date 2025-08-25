import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'providers/selected_profile_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/reports_provider.dart';
import 'providers/activities_provider.dart';
import 'services/database_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';
import 'config/app_config.dart';
import 'ui/common/app_theme.dart';

void main() async {
  // Ensure Flutter is properly initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  final notificationService = NotificationService();
  final db = DatabaseService(notificationService: notificationService);
  final authService = AuthService();
  
  // Initialize services in parallel for better performance
  await Future.wait([
    if (!kIsWeb) notificationService.init(),
    db.init(),
  ]);
  
  try {
    await authService.initFirebase();
  } catch (e) {
    // Firebase not configured; proceed without remote auth (Google sign-in may fail)
    if (kDebugMode) {
      debugPrint('Firebase initialization skipped: $e');
    }
  }
  
  if (kDebugMode) {
    debugPrint('Hi-Doc backend URL: ${AppConfig.backendBaseUrl}');
  }
  
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
        Provider<AuthService>.value(value: authService),
        ChangeNotifierProvider(create: (_) => AuthProvider(authService)),
  ChangeNotifierProvider(create: (_) => SettingsProvider()),
  ChangeNotifierProvider(create: (_) => SelectedProfileProvider()),
        ChangeNotifierProvider(create: (context) => ChatProvider(db: db, authService: context.read<AuthService>())),
        ChangeNotifierProvider(create: (_) => ReportsProvider()),
  // Activities depends on ChatProvider for current profile
        ChangeNotifierProxyProvider<ChatProvider, ActivitiesProvider>(
          create: (context) => ActivitiesProvider(chatProvider: context.read<ChatProvider>()),
          update: (context, chat, previous) => previous ?? ActivitiesProvider(chatProvider: chat),
        ),
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

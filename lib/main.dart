import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/cupertino.dart';

import 'core/supabase_client.dart';
import 'core/models/user_role.dart';
import 'core/translations.dart';
import 'features/admin/admin_dashboard.dart';
import 'features/admin/screens/user_management_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/screens/set_password_screen.dart';
import 'features/facilitator/facilitator_dashboard.dart';
import 'features/klant/client_dashboard.dart';
import 'features/operator/operator_dashboard.dart';
import 'features/auth/no_portals_assigned_screen.dart';
import 'features/admin/screens/factuur_editor_screen.dart';
import 'shared/layouts/mobile_bottom_nav_layout.dart';
import 'providers/theme_provider.dart';
import 'providers/user_provider.dart';
import 'providers/theme_mode_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables.
  // Note: If you renamed it for Netlify earlier, make sure this says "env.txt" instead of ".env".
  await dotenv.load(fileName: "env.txt");

  // Read variables securely - USE THE EXACT VARIABLE NAMES, NOT THE ACTUAL URL!
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    throw Exception('Supabase configuratie ontbreekt in env bestand');
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Load theme first (await), then start realtime updates.
  final themeProvider = ThemeProvider();
  await themeProvider.load();
  themeProvider.startLiveUpdates();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        const radius = BorderRadius.all(Radius.circular(24));
        final shape = RoundedRectangleBorder(borderRadius: radius);

        // Light: clean with a professional deep blue/indigo accent.
        const lightBg = Color(0xFFF6F8FC);
        const lightPrimary = Color(0xFF1E3A8A); // Indigo 900-ish

        const lightText = Color(0xFF1C1C1E);

        ThemeData buildTheme({required Brightness brightness}) {
          final scheme = ColorScheme.fromSeed(
            seedColor: lightPrimary,
            brightness: brightness,
            primary: lightPrimary,
            secondary: lightPrimary,
            surface: Colors.white,
            onSurface: lightText,
          );

          final base = ThemeData(
            colorScheme: scheme,
            useMaterial3: true,
            scaffoldBackgroundColor: lightBg,
            fontFamily: GoogleFonts.inter().fontFamily,
          );

          final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
            displayLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
            displayMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
            displaySmall: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
            headlineLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
            headlineMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
            headlineSmall: GoogleFonts.inter(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
            titleLarge: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
            titleMedium: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.82),
            ),
            titleSmall: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.82),
            ),
            bodyLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w400,
              color: scheme.onSurface,
            ),
            bodyMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w400,
              color: scheme.onSurface,
            ),
            bodySmall: GoogleFonts.inter(
              fontWeight: FontWeight.w400,
              color: scheme.onSurface.withValues(alpha: 0.82),
            ),
            labelLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            labelMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.82),
            ),
            labelSmall: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.82),
            ),
          );

          return base.copyWith(
            textTheme: textTheme,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
                TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
              },
            ),
            cardTheme: CardThemeData(
              shape: shape,
              elevation: 0,
              color: Colors.white,
              shadowColor: Colors.black.withValues(alpha: 0.05),
              margin: const EdgeInsets.all(0),
            ),
            dialogTheme: DialogThemeData(shape: shape),
            dividerColor: scheme.onSurface.withValues(alpha: 0.10),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                shape: shape,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: shape,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                shape: shape,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                side: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.16),
                ),
                foregroundColor: scheme.onSurface,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                shape: shape,
                foregroundColor: scheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(borderRadius: radius),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(
                  color: scheme.primary.withValues(alpha: 0.70),
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: scheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleTextStyle: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: scheme.onSurface,
              ),
            ),
          );
        }

        final themeMode = context.watch<ThemeModeProvider>().mode;

        return MaterialApp(
          title: AppTexts.get('app_title'),
          supportedLocales: const [Locale('nl')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: {
            '/set-password': (_) => const SetPasswordScreen(),
            '/login': (_) => const LoginScreen(),
          },
          theme: buildTheme(brightness: Brightness.light),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor:
                const Color(0xFF131314), // Gemini Background
            cardColor: const Color(0xFF1E1F22), // Gemini Elevated Surface
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1E1F22),
            ),
            primaryColor: const Color(0xFF8AB4F8), // Gemini Accent Blue
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF8AB4F8),
              secondary: Color(0xFF8AB4F8),
              surface: Color(0xFF1E1F22),
              onSurface: Color(0xFFE3E3E3), // Primary Text
            ),
            dividerColor: const Color(0xFF444746), // Subtle border
            textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme)
                .copyWith(
              bodyLarge: const TextStyle(color: Color(0xFFE3E3E3)),
              bodyMedium: const TextStyle(color: Color(0xFFC4C7C5)),
              titleLarge: const TextStyle(
                color: Color(0xFFE3E3E3),
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
              titleMedium: const TextStyle(
                color: Color(0xFFE3E3E3),
                fontWeight: FontWeight.bold,
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF131314),
              foregroundColor: Color(0xFFE3E3E3),
              elevation: 0,
              iconTheme: IconThemeData(color: Color(0xFFE3E3E3)),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Color(0xFF1E1F22),
            ),
          ),
          themeMode: themeMode,
          onGenerateRoute: (settings) {
            if (settings.name == '/set-password') {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const SetPasswordScreen(),
              );
            }
            if (settings.name == '/login') {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const LoginScreen(),
              );
            }
            if (settings.name == '/factuur_aanmaken') {
              return MaterialPageRoute(
                builder: (_) => const FactuurEditorScreen(),
              );
            }
            return null;
          },
          home: const SelectionArea(
            child: AuthGate(),
          ),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  String? _identityFutureUserId;
  Future<void>? _identityFuture;
  late final bool _forceSetPasswordFlow;

  bool _isPasswordLink() {
    // CRITICAL: Check URL string first, before auth stream/session logic.
    // This prevents a navigation deadlock when a stale/broken session exists.
    final url = Uri.base.toString().toLowerCase();
    return url.contains('access_token') ||
        url.contains('type=recovery') ||
        url.contains('type=invite') ||
        url.contains('set-password');
  }

  bool _hasRecoveryOrAccessTokenInUrl() {
    final uri = Uri.base;
    final q = uri.queryParameters;
    final frag = uri.fragment;

    // Supabase on web often puts tokens in the URL fragment, as a query string.
    final fragQuery = Uri.tryParse('https://local/?$frag')?.queryParameters ?? const {};

    final type = (q['type'] ?? fragQuery['type'] ?? '').toLowerCase();
    final hasAccessToken = q.containsKey('access_token') || fragQuery.containsKey('access_token');
    final isRecovery = type == 'recovery' || frag.toLowerCase().contains('recovery');

    return hasAccessToken || isRecovery;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // CRITICAL: Lock the app into SetPasswordScreen if we ever started from a
    // recovery/invite URL. Supabase may later clear the fragment/query, but we
    // must never auto-navigate to dashboard during this flow.
    _forceSetPasswordFlow = _hasRecoveryOrAccessTokenInUrl() || _isPasswordLink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final user = AppSupabase.client.auth.currentUser;
    if (user == null || !mounted) return;
    setState(() {
      _identityFuture = null;
      _identityFutureUserId = null;
    });
    context.read<UserProvider>().loadForCurrentUser();
  }

  void _clearIdentityCache() {
    setState(() {
      _identityFuture = null;
      _identityFutureUserId = null;
    });
  }

  Future<void> _identityFutureForUserId(BuildContext context, String userId) {
    if (_identityFuture == null || _identityFutureUserId != userId) {
      _identityFutureUserId = userId;
      _identityFuture = context.read<UserProvider>().loadForCurrentUser();
    }
    return _identityFuture!;
  }

  /// Default portal when multiple [portal_*] permissions exist: administrator → facilitator → operator → klant.
  Widget _homeForPermissions(BuildContext context, UserProvider userProvider) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    // Emergency: Generator always lands in administrator UI with navigation.
    if (userProvider.isGenerator) return const UserManagementScreen();
    if (userProvider.hasPermission('portal_admin') ||
        userProvider.hasPermission('finance')) {
      return const AdminDashboard();
    }
    if (userProvider.hasPermission('portal_facilitator')) {
      return isDesktop ? const FacilitatorDashboard() : const MobileBottomNavLayout();
    }
    if (userProvider.hasPermission('portal_operator')) {
      return const OperatorDashboard();
    }
    if (userProvider.hasPermission('portal_klant')) {
      return const ClientDashboard();
    }
    return const SizedBox.shrink();
  }

  Widget _homeForRoleFallback(BuildContext context, UserProvider userProvider) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    switch (userProvider.role) {
      case UserRole.generator:
        return const UserManagementScreen();
      case UserRole.administrator:
        return const AdminDashboard();
      case UserRole.facilitator:
        return isDesktop ? const FacilitatorDashboard() : const MobileBottomNavLayout();
      case UserRole.operator:
        return const OperatorDashboard();
      case UserRole.klant:
        return const ClientDashboard();
      case null:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL: If opened via invite/recovery/set-password URL, ignore current session
    // and render the SetPasswordScreen immediately. This avoids an infinite loading
    // loop caused by stale sessions after user re-creation.
    if (_forceSetPasswordFlow || _isPasswordLink()) {
      return const SetPasswordScreen();
    }

    return StreamBuilder(
      stream: AppSupabase.client.auth.onAuthStateChange,
      builder: (context, _) {
        final user = AppSupabase.client.auth.currentUser;
        if (user == null) {
          _identityFutureUserId = null;
          _identityFuture = null;
          context.read<UserProvider>().clear();
          return const LoginScreen();
        }

        return FutureBuilder<void>(
          future: _identityFutureForUserId(context, user.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(AppTexts.get('role_lookup_failed_title')),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppTexts.get('logged_in_as')} ${user.email ?? user.id}',
                      ),
                      const SizedBox(height: 12),
                      Text(AppTexts.get('role_lookup_failed_body')),
                      const SizedBox(height: 8),
                      Text('Fout: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          await Supabase.instance.client.auth.signOut();
                          if (!context.mounted) return;
                          context.read<UserProvider>().clear();
                          Navigator.of(context).pushAndRemoveUntil(
                            CupertinoPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        child: Text(AppTexts.get('button_sign_out')),
                      ),
                    ],
                  ),
                ),
              );
            }

            final userProvider = context.watch<UserProvider>();

            if (userProvider.lastError != null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Kan gegevens niet laden')),
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Er ging iets mis bij het ophalen van uw gegevens.',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Details: ${userProvider.lastError}'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          _clearIdentityCache();
                          context.read<UserProvider>().loadForCurrentUser();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Opnieuw proberen'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Supabase.instance.client.auth.signOut();
                          if (!context.mounted) return;
                          context.read<UserProvider>().clear();
                          Navigator.of(context).pushAndRemoveUntil(
                            CupertinoPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Uitloggen'),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (userProvider.hasAnyPortalPermission) {
              return _homeForPermissions(context, userProvider);
            }

            if (userProvider.role != null) {
              return _homeForRoleFallback(context, userProvider);
            }

            return NoPortalsAssignedScreen(onRetry: _clearIdentityCache);
          },
        );
      },
    );
  }
}

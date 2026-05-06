import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/user_provider.dart';

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _supabase = Supabase.instance.client;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSessionCheckComplete = false;
  bool _isLinkInvalidOrExpired = false;

  Future<void> _logoutToLogin() async {
    try {
      _passwordController.clear();
      _confirmController.clear();
      context.read<UserProvider>().clear();
      await _supabase.auth.signOut();
    } catch (_) {
      // Best-effort: we mainly want to clear the local broken session.
    }

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final session = _supabase.auth.currentSession;
      setState(() {
        _isSessionCheckComplete = true;
        _isLinkInvalidOrExpired = session == null;
      });
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (password.isEmpty || confirm.isEmpty) {
      _showError('Vul alstublieft beide velden in.');
      return;
    }

    if (password.length < 6) {
      _showError('Het wachtwoord moet minimaal 6 tekens lang zijn.');
      return;
    }

    if (password != confirm) {
      _showError('De wachtwoorden komen niet overeen.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authClient = Supabase.instance.client.auth;
      final session = authClient.currentSession;

      if (session == null) {
        _showError('Link ongeldig of verlopen');
        return;
      }

      debugPrint('X-RAY JWT Check: User ID in session is ${session.user.id}');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      await _supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      // CRUCIAAL: wipe any stale/broken session immediately.
      await _supabase.auth.signOut();

      if (!mounted) return;
      context.read<UserProvider>().clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wachtwoord succesvol ingesteld! U kunt nu inloggen.'),
          backgroundColor: Colors.green,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (e is AuthApiException &&
          ((e.code ?? '').toLowerCase() == 'user_not_found' ||
              msg.contains('user_not_found') ||
              msg.contains('user from sub claim'))) {
        _showError(
          'Uw inlogbewijs is verouderd. Log alstublieft uit en gebruik de nieuwste link uit uw e-mail.',
        );
        return;
      }

      _showError('Er is iets misgegaan: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSessionCheckComplete) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

    if (_isLinkInvalidOrExpired) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.link_off_rounded,
                      size: 40,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Link ongeldig of verlopen',
                    style: GoogleFonts.lato(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vraag een nieuwe link aan via inloggen of gebruik de meest recente e-mail.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _logoutToLogin,
                      child: const Text('Terug naar inloggen'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      size: 40,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Wachtwoord instellen',
                  style: GoogleFonts.lato(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kies een veilig wachtwoord om uw account te activeren.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Text(
                  'Nieuw Wachtwoord',
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Minimaal 6 tekens',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() {
                        _obscurePassword = !_obscurePassword;
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Wachtwoord Bevestigen',
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Herhaal uw wachtwoord',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updatePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                            'Account Activeren',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _logoutToLogin,
                    child: const Text('Terug naar inloggen'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


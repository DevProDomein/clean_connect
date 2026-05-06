import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;

  bool _sessionChecked = false;
  Session? _session;

  @override
  void initState() {
    super.initState();

    // CRITICAL: give Supabase time to parse the URL fragment and persist the session.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _session = _supabase.auth.currentSession;
        _sessionChecked = true;
      });
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _goToLogin({String? successMessage}) async {
    if (!mounted) return;
    if (successMessage != null) {
      _snack(successMessage, color: Colors.green);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _signOutAndReturnToLogin({String? successMessage}) async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Best-effort: session wipe is critical, but navigation should still proceed.
    }
    await _goToLogin(successMessage: successMessage);
  }

  String? _validatePassword(String password, String confirm) {
    if (password.isEmpty || confirm.isEmpty) {
      return 'Vul alstublieft beide velden in.';
    }
    if (password.length < 6) {
      return 'Het wachtwoord moet minimaal 6 tekens lang zijn.';
    }
    if (password != confirm) {
      return 'De wachtwoorden komen niet overeen.';
    }
    return null;
  }

  Future<void> _updatePassword() async {
    final newPassword = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();
    final validation = _validatePassword(newPassword, confirm);
    if (validation != null) {
      _snack(validation, color: Colors.redAccent);
      return;
    }

    // Re-check session right before saving to avoid wrong-account updates.
    final session = _supabase.auth.currentSession;
    if (session == null) {
      _snack(
        'Geen geldige sessie gevonden. Gebruik de link uit de meest recente e-mail.',
        color: Colors.redAccent,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      debugPrint('X-RAY JWT Check: User ID in session is ${session.user.id}');

      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      // CRITICAL SECURITY STEP: destroy the temporary link-session immediately.
      await _supabase.auth.signOut();

      await _goToLogin(
        successMessage: 'Wachtwoord ingesteld. Log nu in met uw nieuwe wachtwoord.',
      );
    } on AuthException catch (e) {
      final msg = (e.message).toLowerCase();
      if (msg.contains('expired') ||
          msg.contains('invalid') ||
          msg.contains('token') ||
          msg.contains('otp') ||
          msg.contains('link')) {
        _snack(
          'Link verlopen of ongeldig. Gebruik de link uit de meest recente e-mail.',
          color: Colors.redAccent,
        );
        return;
      }
      _snack('Authenticatie fout: ${e.message}', color: Colors.redAccent);
    } catch (e) {
      _snack('Er is iets misgegaan: ${e.toString()}', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _shell({required Widget child}) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.lato(
      fontSize: 34,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.8,
    );

    if (!_sessionChecked) {
      return _shell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CupertinoActivityIndicator(),
            SizedBox(height: 14),
            Text('Bezig met laden...'),
          ],
        ),
      );
    }

    if (_session == null) {
      return _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded, size: 44, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text('Account Activeren', style: titleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Geen geldige sessie gevonden. Gebruik de link uit de meest recente e-mail.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: () => _signOutAndReturnToLogin(),
                child: const Text('Terug naar inloggen'),
              ),
            ),
          ],
        ),
      );
    }

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_reset_rounded, size: 44, color: Colors.blueAccent),
          const SizedBox(height: 16),
          Text('Account Activeren', style: titleStyle, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Stel een nieuw wachtwoord in om uw account te activeren.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 26),
          Text('Nieuw Wachtwoord', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Minimaal 6 tekens',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Bevestig Wachtwoord', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _isLoading ? null : _updatePassword(),
            decoration: const InputDecoration(
              hintText: 'Herhaal uw wachtwoord',
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _isLoading ? null : _updatePassword,
              child: _isLoading
                  ? const CupertinoActivityIndicator()
                  : const Text('Wachtwoord Instellen & Inloggen'),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: _isLoading ? null : () => _signOutAndReturnToLogin(),
            child: const Text('Terug naar inloggen'),
          ),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  final bool accountExists;
  final VoidCallback onAuthenticated;

  const LoginScreen({
    super.key,
    required this.accountExists,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creating = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_creating) {
        await AuthService.instance.createAccount(username, password);
        widget.onAuthenticated();
      } else if (await AuthService.instance.verify(username, password)) {
        widget.onAuthenticated();
      } else {
        setState(() => _error = 'Incorrect username or password.');
      }
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString() ?? 'Invalid account details.');
    } catch (_) {
      setState(() => _error = 'Unable to complete authentication.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useDeviceAuth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final authenticated = await BiometricService.instance.authenticate();
    if (!mounted) return;
    setState(() => _loading = false);
    if (authenticated) {
      widget.onAuthenticated();
    } else {
      setState(() => _error = 'Device authentication failed. Use your password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canUseDeviceAuth = widget.accountExists && !_creating;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, size: 64, color: colors.accentStart),
                const SizedBox(height: 16),
                Text('Aegis', style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                TextField(controller: _usernameController, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _passwordController, obscureText: true, onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.danger, fontSize: 12.5)),
                ],
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading ? null : _submit, child: Text(_loading ? 'Please wait...' : (_creating ? 'Create Account' : 'Log In')))),
                if (canUseDeviceAuth)
                  TextButton.icon(onPressed: _loading ? null : _useDeviceAuth, icon: const Icon(Icons.fingerprint_rounded), label: const Text('Use device authentication')),
                TextButton(onPressed: _loading ? null : () => setState(() { _creating = !_creating; _error = null; }), child: Text(_creating ? 'Already have an account? Log in' : 'New here? Create an account')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../routing/routes.dart';
import 'auth_controller.dart';
import 'auth_layout.dart';
import 'validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(identifier: _identifier.text.trim(), password: _password.text);
      // Router redirects once the state becomes Authenticated.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = FormFailure.from(e).message ?? 'Please check your details.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.welcome)),
      ),
      children: [
        Text('Welcome back', style: text.displayMedium),
        const SizedBox(height: AppSpacing.sm),
        Text('Sign in to continue your journal.', style: text.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _identifier,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Email or username',
                ),
                validator: (v) =>
                    Validators.required(v, 'Enter your email or username'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => Validators.required(v, 'Enter your password'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FormErrorText(_error),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign in'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: () => context.go(AppRoutes.register),
          child: const Text('New to ANGON? Create an account'),
        ),
      ],
    );
  }
}

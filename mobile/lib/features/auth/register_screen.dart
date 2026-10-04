import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../routing/routes.dart';
import 'auth_controller.dart';
import 'auth_layout.dart';
import 'validators.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;
  Map<String, String> _serverErrors = {};

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _check(String field, String? Function(String?) local, String? v) =>
      local(v) ?? _serverErrors[field];

  Future<void> _submit() async {
    setState(() => _serverErrors = {});
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            email: _email.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
          );
    } catch (e) {
      if (!mounted) return;
      final failure = FormFailure.from(e);
      setState(() {
        _submitting = false;
        _error = failure.message;
        _serverErrors = failure.fields;
      });
      _formKey.currentState!.validate(); // surface per-field server errors
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
        Text('Create your account', style: text.displayMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Join travellers and storytellers documenting places.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => _check('email', Validators.email, v),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.newUsername],
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                ),
                validator: (v) => _check('username', Validators.username, v),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters',
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
                validator: (v) => _check('password', Validators.newPassword, v),
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
              : const Text('Create account'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: () => context.go(AppRoutes.login),
          child: const Text('Already have an account? Sign in'),
        ),
      ],
    );
  }
}

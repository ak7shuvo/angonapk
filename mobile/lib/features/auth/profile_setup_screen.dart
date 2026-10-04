import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../models/user.dart';
import 'auth_controller.dart';
import 'auth_layout.dart';
import 'validators.dart';

/// Shown after sign-up (and on later sign-ins) until the profile is complete.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _location = TextEditingController();
  CreatorType? _type;
  bool _submitting = false;
  String? _error;
  String? _typeError;

  @override
  void initState() {
    super.initState();
    final user = switch (ref.read(authControllerProvider)) {
      Authenticated(:final user) => user,
      _ => null,
    };
    _name.text = user?.profile.displayName ?? '';
    _bio.text = user?.profile.bio ?? '';
    _location.text = user?.profile.location ?? '';
    _type = user?.profile.creatorType;
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    setState(
      () => _typeError = _type == null ? 'Pick what describes you best' : null,
    );
    if (!valid || _type == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            displayName: _name.text.trim(),
            bio: _bio.text.trim(),
            location: _location.text.trim(),
            creatorType: _type,
          );
      // Router redirects to Home once the profile is complete.
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
    final theme = Theme.of(context);
    return AuthLayout(
      children: [
        Text('Tell us about you', style: theme.textTheme.displayMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is how other travellers and storytellers will see you.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => Validators.required(v, 'Enter your name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _location,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  hintText: 'e.g. Sylhet, Bangladesh',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _bio,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Bio (optional)',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('I AM A', style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final type in CreatorType.values)
              ChoiceChip(
                label: Text(type.label),
                selected: _type == type,
                onSelected: (_) => setState(() {
                  _type = type;
                  _typeError = null;
                }),
              ),
          ],
        ),
        if (_typeError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _typeError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        FormErrorText(_error),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}

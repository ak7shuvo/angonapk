import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';

/// Scrollable, keyboard-safe page body shared by the auth screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.children, this.appBar});
  final List<Widget> children;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
              vertical: AppSpacing.lg,
            ),
            children: children,
          ),
        ),
      ),
    ),
  );
}

/// Inline form-level error (network / server / bad credentials).
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        message!,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// Splits an API error into a form-level message and per-field messages.
class FormFailure {
  const FormFailure({this.message, this.fields = const {}});
  final String? message;
  final Map<String, String> fields;

  factory FormFailure.from(Object error) {
    if (error is ValidationException && error.fieldErrors.isNotEmpty) {
      return FormFailure(fields: error.fieldErrors);
    }
    if (error is AppException) return FormFailure(message: error.message);
    return const FormFailure(
      message: 'Something went wrong. Please try again.',
    );
  }
}

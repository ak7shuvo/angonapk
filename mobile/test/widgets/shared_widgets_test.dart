import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('error state maps exceptions to messages and retries', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorState(
            error: const NetworkException(),
            onRetry: () => retried = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
    expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
  });

  testWidgets('renders Bengali text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: Icons.place, title: 'জাফলং'),
        ),
      ),
    );
    expect(find.text('জাফলং'), findsOneWidget);
  });
}

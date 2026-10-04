import 'package:angon/app.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/core/network/api_client.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineApi implements ApiClient {
  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async =>
      throw const NetworkException();
  @override
  Future<dynamic> post(String path, {Object? body}) async =>
      throw const NetworkException();
  @override
  Future<dynamic> put(String path, {Object? body}) async =>
      throw const NetworkException();
  @override
  Future<dynamic> patch(String path, {Object? body}) async =>
      throw const NetworkException();
  @override
  Future<dynamic> delete(String path) async => throw const NetworkException();
}

Widget _app() => ProviderScope(
  overrides: [apiClientProvider.overrideWithValue(_OfflineApi())],
  child: const AngonApp(),
);

void main() {
  testWidgets('shows five tabs and navigates between them', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    for (final label in ['HOME', 'EXPLORE', 'CREATE', 'STORIES', 'PROFILE']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Your journal starts here'), findsOneWidget);

    await tester.tap(find.text('STORIES'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Long-form travel'), findsOneWidget);
  });

  testWidgets('home reports unreachable backend without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Backend: unreachable'), findsOneWidget);
  });

  testWidgets('shared states render', (tester) async {
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

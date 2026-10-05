// Real client ↔ real API: reporting content.
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/models/report.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('E2E_API_BASE_URL');

Future<ProviderContainer> _signedIn(String username) async {
  final c = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: _baseUrl,
        ),
      ),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
    ],
  );
  addTearDown(c.dispose);
  c.read(authControllerProvider);
  for (
    var i = 0;
    i < 100 && c.read(authControllerProvider) is AuthChecking;
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  await c
      .read(authControllerProvider.notifier)
      .register(
        email: '$username@example.com',
        username: username,
        password: 'correct-horse-1',
      );
  return c;
}

void main() {
  final skip = _baseUrl.isEmpty ? 'set E2E_API_BASE_URL to run' : null;

  test('reports against the real API', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final author = await _signedIn('ra_$stamp'.substring(0, 18));
    final reader = await _signedIn('rb_$stamp'.substring(0, 18));
    final authorUser =
        (author.read(authControllerProvider) as Authenticated).user;
    final post = await author
        .read(postRepositoryProvider)
        .createPost(body: 'report me');
    final reports = reader.read(reportRepositoryProvider);

    await reports.report(
      target: ReportTarget.post,
      targetId: post.id,
      reason: ReportReason.spam,
      details: 'looks like an ad',
    );
    await reports.report(
      target: ReportTarget.user,
      targetId: authorUser.id,
      reason: ReportReason.harassment,
    );

    // Duplicates and self-reports are refused with a readable message.
    await expectLater(
      reports.report(
        target: ReportTarget.post,
        targetId: post.id,
        reason: ReportReason.hate,
      ),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          contains('already reported'),
        ),
      ),
    );
    await expectLater(
      author
          .read(reportRepositoryProvider)
          .report(
            target: ReportTarget.post,
            targetId: post.id,
            reason: ReportReason.spam,
          ),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      reports.report(
        target: ReportTarget.post,
        targetId: '00000000-0000-4000-8000-000000000000',
        reason: ReportReason.spam,
      ),
      throwsA(isA<NotFoundException>()),
    );
  }, skip: skip);
}

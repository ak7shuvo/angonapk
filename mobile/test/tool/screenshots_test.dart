// Developer tool, not a regression test: renders the main screens to PNG files
// for design review. It does nothing unless SCREENSHOT_DIR is set.
//
//   flutter test test/tool/screenshots_test.dart --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Uses the fake backend and the bundled fonts; photos show their placeholders.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:angon/routing/app_router.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/fake_map.dart';
import '../support/harness.dart';

const _dir = String.fromEnvironment('SCREENSHOT_DIR');

const _routes = {
  'home': '/',
  'explore': '/explore',
  'stories': '/stories',
  'profile': '/profile',
  'notifications': '/notifications',
  'place': '/places/jaflong',
  'post': '/posts/p1',
  'story': '/story/s1',
  'map': '/map',
  'search': '/search',
  'compose': '/create',
};

/// Test binding renders with the blocky "Ahem" font unless fonts are loaded.
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('Newsreader', 'assets/fonts/Newsreader.ttf');
  await load('Inter', 'assets/fonts/Inter.ttf');
  await load('NotoSerifBengali', 'assets/fonts/NotoSerifBengali.ttf');
  await load('NotoSansBengali', 'assets/fonts/NotoSansBengali.ttf');
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    await load(
      'MaterialIcons',
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
}

void main() {
  setUpAll(() async {
    if (_dir.isNotEmpty) await _loadFonts();
  });

  for (final dark in [false, true]) {
    testWidgets('screenshots (${dark ? 'dark' : 'light'})', (tester) async {
      tester.view.physicalSize = const Size(780, 1688); // 390x844 @2x
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearAllTestValues();
      });

      final backend = FakeBackend()..seedUser('rahim_bd', 'pw-12345678');
      backend.seedUser('nusrat', 'pw-12345678');
      backend.feed
        ..add(
          postJson(
            'p1',
            body: 'আজ সকালে জাফলংয়ে পাহাড়ের নিচে স্বচ্ছ জলের পাশে বসে ছিলাম। এখানকার নীরবতা ভাষায় প্রকাশ করা কঠিন।',
            location: 'জাফলং, সিলেট',
            username: 'nusrat',
            displayName: '[Seed] নুসরাত',
            place: placeJson('jaflong', name: 'Jaflong', nameLocal: 'জাফলং'),
          ),
        )
        ..add(
          postJson(
            'p2',
            body: 'Early light over the haor. The water was completely still.',
            location: 'Tanguar Haor, Sunamganj',
            username: 'seed_rahim',
          ),
        );
      backend.stories
        ..add(
          storyJson(
            's1',
            title: 'Jaflong: A Day of Quiet',
            content: 'The morning began slowly. I sat by the river and listened to the water.\n\n## Stone and current\n\nWater moves across the stones and nobody is in a hurry.\n\n> Some places are not for seeing but for feeling quietly.',
            username: 'nusrat',
          ),
        )
        ..add(
          storyJson('s2', title: 'পাহাড়ের কোলে এক সকাল', username: 'nusrat'),
        );
      backend.places
        ..add(
          placeJson(
            'jaflong',
            name: 'Jaflong',
            nameLocal: 'জাফলং',
            description: 'A riverside area near the hills. Development sample description.',
            postCount: 3,
            storyCount: 1,
          ),
        )
        ..add(
          placeJson('sreemangal', name: 'Sreemangal', nameLocal: 'শ্রীমঙ্গল'),
        );
      backend.notifications.addAll([
        notificationJson('n1', data: {'preview': 'Early light over the haor'}),
        notificationJson(
          'n2',
          type: 'comment',
          targetType: 'comment',
          data: {'post_id': 'p1', 'preview': 'সুন্দর ছবি!'},
        ),
        notificationJson(
          'n3',
          type: 'follow',
          actor: 'nusrat',
          targetType: 'user',
          data: {'username': 'nusrat'},
          isRead: true,
        ),
      ]);

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: buildTestApp(
            backend,
            InMemoryTokenStorage(backend.issueToken('rahim_bd')),
            overrides: [mapAdapterProvider.overrideWithValue(FakeMapAdapter())],
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      final router = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      ).read(routerProvider);

      for (final entry in _routes.entries) {
        router.go(entry.value);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$_dir/${entry.key}-${dark ? 'dark' : 'light'}.png',
          );
          await file.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
    }, skip: _dir.isEmpty);
  }

  testWidgets('screenshots (signed out)', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: buildTestApp(FakeBackend(), InMemoryTokenStorage()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(routerProvider);
    for (final entry in {
      'welcome': '/welcome',
      'login': '/login',
      'register': '/register',
    }.entries) {
      router.go(entry.value);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$_dir/${entry.key}-light.png');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  }, skip: _dir.isEmpty);
}

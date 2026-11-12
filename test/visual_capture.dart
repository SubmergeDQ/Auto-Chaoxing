// 视觉取证工具：用 Flutter 真实渲染导出标准视口 PNG。
// 文件名不以 _test.dart 结尾，不会被 CI 的 `flutter test` 自动收集；显式运行：
//   flutter test test/visual_capture.dart --update-goldens
// 产物写入 test/goldens/（过程文件，不入库），数据来自 test/support/fake_api.dart。
// flutter_test 默认用 Ahem 占位字体，中文与图标会变成方块，所以注入等线 + MaterialIcons。
import 'dart:io';
import 'dart:typed_data';

import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/main.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

const String _cnFontFamily = 'AcxCjk';

void main() {
  testWidgets('capture standard viewports', (WidgetTester tester) async {
    String? family;
    await tester.binding.runAsync(() async {
      family = await loadTestFonts();
    });

    await capture(
      tester: tester,
      name: 'desktop-courses',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      expandFirstChapter: true,
    );
    await capture(
      tester: tester,
      name: 'desktop-empty',
      size: const Size(1440, 900),
      state: AppState(api: FakeChaoxingApi()),
      fontFamily: family,
    );
    await capture(
      tester: tester,
      name: 'desktop-selfcheck',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      page: 1,
    );
    await capture(
      tester: tester,
      name: 'desktop-settings',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      page: 2,
    );
    await capture(
      tester: tester,
      name: 'mobile-courses',
      size: const Size(390, 844),
      state: signedInState(),
      fontFamily: family,
    );
    await capture(
      tester: tester,
      name: 'mobile-chapters',
      size: const Size(390, 844),
      state: signedInState(),
      fontFamily: family,
      openCourse: true,
    );
    await capture(
      tester: tester,
      name: 'mobile-empty',
      size: const Size(390, 844),
      state: AppState(api: FakeChaoxingApi()),
      fontFamily: family,
    );
  });
}

/// 注入中文字体与 MaterialIcons；找不到时对应字符会退化为占位方块。
/// 返回中文字体名供 ThemeData.fontFamily 使用，没有则 null。
Future<String?> loadTestFonts() async {
  String? family;
  for (final String path in <String>[
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
  ]) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    final Uint8List bytes = file.readAsBytesSync();
    final FontLoader loader = FontLoader(_cnFontFamily)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    family = _cnFontFamily;
    break;
  }

  final String flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'D:\dev\flutter';
  for (final String path in <String>[
    '$flutterRoot\\bin\\cache\\artifacts\\material_fonts\\materialicons-regular.otf',
    r'D:\dev\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    '/d/dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ]) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    final Uint8List bytes = file.readAsBytesSync();
    final FontLoader loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    break;
  }
  return family;
}

AppState signedInState() {
  final AppState state = AppState(
    api: FakeChaoxingApi(
      courses: kDemoCourses,
      chapters: kDemoChapters,
      points: kDemoPoints,
    ),
  );
  state.profile = const Profile(
    uid: '10086',
    name: '林知远',
    fid: '666',
    school: '示例大学',
  );
  state.coursesState = LoadState.ready;
  state.courses = kDemoCourses;
  state.selectedCourse = kDemoCourses.first;
  state.chaptersState = LoadState.ready;
  state.chapters = kDemoChapters;
  return state;
}

Future<void> capture({
  required WidgetTester tester,
  required String name,
  required Size size,
  required AppState state,
  String? fontFamily,
  int page = 0,
  bool expandFirstChapter = false,
  bool openCourse = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final GlobalKey boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: AutoChaoxingApp(
        key: ValueKey<String>(name),
        state: state,
        fontFamily: fontFamily,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));

  if (page == 1) {
    final Finder nav = find.text('协议自检');
    if (nav.evaluate().isNotEmpty) {
      await tester.tap(nav.first);
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  if (page == 2) {
    final Finder nav = find.text('设置');
    if (nav.evaluate().isNotEmpty) {
      await tester.tap(nav.first);
      await tester.pump(const Duration(milliseconds: 300));
      final Finder disconnect = find.text('断开连接');
      if (disconnect.evaluate().isNotEmpty) {
        await tester.ensureVisible(disconnect);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
  }
  if (openCourse) {
    final Finder course = find.text('高等数学（上）');
    if (course.evaluate().isNotEmpty) {
      await tester.tap(course.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  if (expandFirstChapter) {
    final Finder chapter = find.text('第一章 函数与极限');
    if (chapter.evaluate().isNotEmpty) {
      await tester.tap(chapter.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  await expectLater(
    find.byKey(boundaryKey),
    matchesGoldenFile('goldens/$name.png'),
  );
}

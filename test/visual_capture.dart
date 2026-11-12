// 视觉取证工具：用 Flutter 真实渲染导出标准视口、交互态与异常态 PNG。
// 文件名不以 _test.dart 结尾，不会被 CI 的 `flutter test` 自动收集；显式运行：
//   flutter test test/visual_capture.dart --update-goldens
// 产物写入 test/goldens/（过程文件，不入库），数据来自 test/support/fake_api.dart。
// flutter_test 默认用 Ahem 占位字体，中文与图标会变成方块，所以注入等线 + MaterialIcons。
import 'dart:io';
import 'dart:typed_data';

import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:auto_chaoxing/main.dart';
import 'package:auto_chaoxing/platform/platform_services.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:auto_chaoxing/state/keep_alive_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_run_keeper.dart';

const String _cnFontFamily = 'AcxCjk';

const Profile kDemoProfile = Profile(
  uid: '10086',
  name: '林知远',
  fid: '666',
  school: '示例大学',
);

void main() {
  testWidgets('capture standard viewports', (WidgetTester tester) async {
    String? family;
    await tester.binding.runAsync(() async {
      family = await loadTestFonts();
    });

    // 桌面：常态、空态、登录表单、登录失败、自检、设置、断开连接后
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
      state: AppState(api: FakeChaoxingApi(), runKeeper: const NoopRunKeeper()),
      fontFamily: family,
    );
    await capture(
      tester: tester,
      name: 'desktop-login',
      size: const Size(1440, 900),
      state: AppState(api: FakeChaoxingApi(), runKeeper: const NoopRunKeeper()),
      fontFamily: family,
      showLoginDialog: true,
    );
    await capture(
      tester: tester,
      name: 'desktop-login-error',
      size: const Size(1440, 900),
      state: AppState(
        api: FakeChaoxingApi(loginError: '密码错误，请检查后重试'),
        runKeeper: const NoopRunKeeper(),
      ),
      fontFamily: family,
      fillLoginAndSubmit: true,
    );
    await capture(
      tester: tester,
      name: 'desktop-selfcheck',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      page: 2,
    );
    // 自检卡的三种状态：计时中、计时连续、计时被押后。
    await capture(
      tester: tester,
      name: 'desktop-selfcheck-probe-running',
      size: const Size(1440, 900),
      state: probeState(
        phase: ProbePhase.running,
        ticks: 7,
        maxGap: const Duration(seconds: 15),
        elapsed: const Duration(minutes: 1, seconds: 45),
        keeping: true,
      ),
      fontFamily: family,
      page: 2,
    );
    await capture(
      tester: tester,
      name: 'desktop-selfcheck-probe-done',
      size: const Size(1440, 900),
      state: probeState(
        phase: ProbePhase.done,
        ticks: 12,
        maxGap: const Duration(seconds: 15),
        elapsed: const Duration(minutes: 3),
      ),
      fontFamily: family,
      page: 2,
    );
    await capture(
      tester: tester,
      name: 'desktop-selfcheck-probe-interrupted',
      size: const Size(1440, 900),
      state: probeState(
        phase: ProbePhase.done,
        ticks: 11,
        maxGap: const Duration(seconds: 75),
        elapsed: const Duration(minutes: 3),
      ),
      fontFamily: family,
      page: 2,
    );
    await capture(
      tester: tester,
      name: 'desktop-settings',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      page: 3,
    );
    await capture(
      tester: tester,
      name: 'desktop-disconnected',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      page: 3,
      tapDisconnect: true,
    );

    // 桌面：加载 / 失败 / 需要人工 三类异常态
    await capture(
      tester: tester,
      name: 'desktop-loading',
      size: const Size(1440, 900),
      state: coursesState(LoadState.loading),
      fontFamily: family,
    );
    await capture(
      tester: tester,
      name: 'desktop-error',
      size: const Size(1440, 900),
      state: coursesState(
        LoadState.error,
        message: '连接超时。请检查网络后重试，或稍后再打开课程列表。',
      ),
      fontFamily: family,
    );
    await capture(
      tester: tester,
      name: 'desktop-chapters-loading',
      size: const Size(1440, 900),
      state: signedInState()
        ..chaptersState = LoadState.loading
        ..chapters = <Chapter>[],
      fontFamily: family,
    );
    await capture(
      tester: tester,
      name: 'desktop-chapters-error',
      size: const Size(1440, 900),
      state: signedInState()
        ..chaptersState = LoadState.error
        ..chapters = <Chapter>[]
        ..chaptersError = '暂时没能读到章节，请检查网络后重试。',
      fontFamily: family,
    );
    await capture(
      tester: tester,
      name: 'desktop-chapter-locked',
      size: const Size(1440, 900),
      state: signedInState(cardsErrorCode: 'locked'),
      fontFamily: family,
      expandFirstChapter: true,
    );
    // 执行前的确认框：说明处理范围与「遇到人工验证会停下」。
    await capture(
      tester: tester,
      name: 'desktop-run-confirm',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      expandFirstChapter: true,
      tapRun: true,
    );

    // 桌面：任务执行页的空态 / 运行中 / 已完成
    await capture(
      tester: tester,
      name: 'desktop-run-idle',
      size: const Size(1440, 900),
      state: signedInState(),
      fontFamily: family,
      page: 1,
    );
    await capture(
      tester: tester,
      name: 'desktop-run-running',
      size: const Size(1440, 900),
      state: runState(phase: TaskPhase.running),
      fontFamily: family,
      page: 1,
    );
    await capture(
      tester: tester,
      name: 'desktop-run-done',
      size: const Size(1440, 900),
      state: runState(phase: TaskPhase.succeeded),
      fontFamily: family,
      page: 1,
    );
    await capture(
      tester: tester,
      name: 'desktop-run-attention',
      size: const Size(1440, 900),
      state: runState(phase: TaskPhase.needsAttention),
      fontFamily: family,
      page: 1,
    );
    await capture(
      tester: tester,
      name: 'desktop-run-failed',
      size: const Size(1440, 900),
      state: runState(phase: TaskPhase.failed),
      fontFamily: family,
      page: 1,
    );
    // 已有任务在执行时，章节入口禁用并写明原因。
    await capture(
      tester: tester,
      name: 'desktop-run-busy',
      size: const Size(1440, 900),
      state: runState(phase: TaskPhase.running),
      fontFamily: family,
      expandFirstChapter: true,
    );

    // 移动端：课程列表、章节下钻、自检、设置、空态、执行中
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
      name: 'mobile-chapters-expanded',
      size: const Size(390, 844),
      state: signedInState(),
      fontFamily: family,
      openCourse: true,
      expandFirstChapter: true,
    );
    await capture(
      tester: tester,
      name: 'mobile-run-running',
      size: const Size(390, 844),
      state: runState(phase: TaskPhase.running),
      fontFamily: family,
      page: 1,
    );
    await capture(
      tester: tester,
      name: 'mobile-selfcheck',
      size: const Size(390, 844),
      state: signedInState(),
      fontFamily: family,
      page: 2,
    );
    await capture(
      tester: tester,
      name: 'mobile-settings',
      size: const Size(390, 844),
      state: signedInState(),
      fontFamily: family,
      page: 3,
    );
    await capture(
      tester: tester,
      name: 'mobile-empty',
      size: const Size(390, 844),
      state: AppState(api: FakeChaoxingApi(), runKeeper: const NoopRunKeeper()),
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

AppState coursesState(LoadState state, {String? message}) {
  final AppState s = AppState(api: FakeChaoxingApi());
  s.profile = kDemoProfile;
  s.coursesState = state;
  s.coursesError = message;
  return s;
}

AppState signedInState({String? cardsErrorCode}) {
  final AppState state = AppState(
    api: FakeChaoxingApi(
      courses: kDemoCourses,
      chapters: kDemoChapters,
      points: kDemoPoints,
      cardsErrorCode: cardsErrorCode,
    ),
    // 用 supported=true 的替身：真机上自检页有保活卡片，截图必须一致。
    runKeeper: RunKeeperStub(),
  );
  state.profile = kDemoProfile;
  state.coursesState = LoadState.ready;
  state.courses = kDemoCourses;
  state.selectedCourse = kDemoCourses.first;
  state.chaptersState = LoadState.ready;
  state.chapters = kDemoChapters;
  return state;
}

/// 把保活自检摆成确定的状态，便于拍「计时中 / 连续 / 被押后」三张。
AppState probeState({
  required ProbePhase phase,
  int ticks = 0,
  Duration maxGap = Duration.zero,
  Duration elapsed = Duration.zero,
  bool keeping = false,
}) {
  final AppState state = signedInState();
  state.probe.seedForPreview(
    phase: phase,
    ticks: ticks,
    maxGap: maxGap,
    elapsed: elapsed,
    keeping: keeping,
  );
  return state;
}

/// 注入一次执行快照，让执行页有确定的进度与日志可渲染，不发任何请求。
AppState runState({required TaskPhase phase}) {
  final AppState state = signedInState();
  final DateTime start = DateTime(2026, 11, 12, 19, 40, 8);
  DateTime at(int minutes, int seconds) =>
      start.add(Duration(minutes: minutes, seconds: seconds));

  final List<TaskLog> logs = <TaskLog>[
    TaskLog('开始处理「第一章 函数与极限」，共 2 个视频任务点', at: start),
    TaskLog('开始：1.1 映射与函数', at: at(0, 2)),
    TaskLog('1.1 映射与函数：已上报 0:00 / 10:00', level: 'trace', at: at(0, 4)),
    TaskLog('1.1 映射与函数：已上报 5:00 / 10:00', level: 'trace', at: at(2, 0)),
    TaskLog('通过：1.1 映射与函数', at: at(3, 12)),
  ];

  late final int done;
  late final String message;
  switch (phase) {
    case TaskPhase.running:
      done = 1;
      message = '';
      logs
        ..add(TaskLog('开始：1.2 数列的极限', at: at(3, 14)))
        ..add(TaskLog('1.2 数列的极限：已上报 1:00 / 10:00', level: 'trace', at: at(3, 19)));
    case TaskPhase.succeeded:
      done = 2;
      message = '2 / 2 个任务点已通过';
      logs
        ..add(TaskLog('开始：1.2 数列的极限', at: at(3, 14)))
        ..add(TaskLog('通过：1.2 数列的极限', at: at(4, 20)))
        ..add(TaskLog('结束：$message', at: at(4, 23)));
    case TaskPhase.needsAttention:
      done = 1;
      message = '登录已失效，请重新连接账号后再继续';
      logs
        ..add(TaskLog('开始：1.2 数列的极限', at: at(3, 14)))
        ..add(TaskLog(message, level: 'error', at: at(3, 19)));
    case TaskPhase.failed:
      done = 1;
      message = '1 / 2 个任务点已通过，1 个未通过';
      logs
        ..add(TaskLog('开始：1.2 数列的极限', at: at(3, 14)))
        ..add(TaskLog('未通过：1.2 数列的极限（可能有人脸抽检或倍速限制）',
            level: 'warn', at: at(4, 20)))
        ..add(TaskLog('结束：$message', level: 'warn', at: at(4, 23)));
    default:
      done = 0;
      message = '';
  }

  final bool finished =
      phase == TaskPhase.succeeded || phase == TaskPhase.failed || phase == TaskPhase.needsAttention;

  state.run.seedForPreview(
    courseName: '高等数学（上）',
    chapterTitle: '第一章 函数与极限',
    course: kDemoCourses.first,
    chapter: kDemoChapters.first,
    startedAt: start,
    finishedAt: finished ? at(4, 23) : null,
    progress: TaskProgress(
      phase: phase,
      current: phase == TaskPhase.running ? '1.2 数列的极限' : '',
      done: done,
      total: 2,
      message: message,
    ),
    logs: logs,
  );
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
  bool showLoginDialog = false,
  bool fillLoginAndSubmit = false,
  bool tapDisconnect = false,
  bool tapRun = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final bool wide = size.width >= 1000;
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

  if (showLoginDialog || fillLoginAndSubmit) {
    final Finder login = find.text('连接账号');
    if (login.evaluate().isNotEmpty) {
      await tester.tap(login.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  if (fillLoginAndSubmit) {
    final Finder fields = find.byType(TextFormField);
    if (fields.evaluate().length >= 2) {
      await tester.enterText(fields.at(0), '13800000000');
      await tester.enterText(fields.at(1), 'wrong-password');
      await tester.pump(const Duration(milliseconds: 100));
      final Finder submit = find.text('连接');
      if (submit.evaluate().isNotEmpty) {
        await tester.tap(submit.first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
  }
  if (page == 1) {
    // 侧栏叫「任务执行」，窄屏底栏叫「执行」。
    final Finder nav = find.text(wide ? '任务执行' : '执行');
    if (nav.evaluate().isNotEmpty) {
      await tester.tap(nav.first);
      // 底栏选中胶囊有过渡动画，等它走完再截图，否则选中态会停在上一项。
      await tester.pump(const Duration(milliseconds: 600));
    }
  }
  if (page == 2) {
    // 侧栏叫「协议自检」，窄屏底栏叫「自检」。
    final Finder nav = find.text(wide ? '协议自检' : '自检');
    if (nav.evaluate().isNotEmpty) {
      await tester.tap(nav.first);
      await tester.pump(const Duration(milliseconds: 600));
    }
  }
  if (page == 3) {
    final Finder nav = find.text('设置');
    if (nav.evaluate().isNotEmpty) {
      await tester.tap(nav.first);
      await tester.pump(const Duration(milliseconds: 600));
      final Finder disconnect = find.text('断开连接');
      if (disconnect.evaluate().isNotEmpty) {
        await tester.ensureVisible(disconnect);
        await tester.pump(const Duration(milliseconds: 300));
        if (tapDisconnect) {
          await tester.tap(disconnect);
          await tester.pump(const Duration(milliseconds: 300));
        }
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
  if (tapRun) {
    final Finder run = find.text('执行本章视频');
    if (run.evaluate().isNotEmpty) {
      await tester.ensureVisible(run.first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(run.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  await expectLater(
    find.byKey(boundaryKey),
    matchesGoldenFile('goldens/$name.png'),
  );
}

import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:auto_chaoxing/main.dart';
import 'package:auto_chaoxing/platform/keep_alive_settings.dart';
import 'package:auto_chaoxing/platform/platform_services.dart';
import 'package:auto_chaoxing/platform/window_shell.dart';
import 'package:auto_chaoxing/core/update/app_release.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:auto_chaoxing/state/keep_alive_probe.dart';
import 'package:auto_chaoxing/state/update_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_platform.dart';
import 'support/fake_run_keeper.dart';
import 'support/fake_session.dart';
import 'support/fake_update.dart';

/// 检查更新在 widget 测试里必须被挡住：既不该真去打 GitHub，
/// 也不该让 bootstrap 的自动检查影响首帧。
UpdateState noUpdateState() => UpdateState(
      checker: FakeUpdateChecker(noRelease: true),
      installer: FakeInstaller(),
      throttle: UpdateThrottle(
        read: () async => DateTime.now(),
        write: (DateTime _) async {},
      ),
      currentVersion: '0.4.1',
      quitApp: () async {},
    );

void main() {
  AppState signedInState({
    List<Course> courses = kDemoCourses,
    RunKeeper? keeper,
    KeepAliveSettings? keepAlive,
    WindowShell? shell,
  }) {
    final AppState state = AppState(
      api: FakeChaoxingApi(courses: courses),
      // 测试环境没有原生通道：显式用 Noop，避免多出一条「保活未启用」的告警干扰断言。
      runKeeper: keeper ?? const NoopRunKeeper(),
      // 同上：Windows 上默认实现会去建托盘，测试里一律用 Noop。
      keepAliveSettings: keepAlive ?? const NoopKeepAliveSettings(),
      windowShell: shell ?? const NoopWindowShell(),
      update: noUpdateState(),
    );
    state.profile = const Profile(
      uid: '10086',
      name: '林知远',
      fid: '666',
      school: '示例大学',
    );
    state.coursesState = LoadState.ready;
    state.courses = courses;
    return state;
  }

  AppState courseSelectedState({
    List<TaskPoint> points = kDemoPoints,
    RunKeeper? keeper,
  }) {
    final FakeChaoxingApi api = FakeChaoxingApi(
      courses: kDemoCourses,
      chapters: kDemoChapters,
      points: points,
    );
    // 签到要用 api.profile 里的 uid/name/fid，真实环境登录后由 fetchProfile 写入。
    api.profile = api.demoProfile;
    final AppState state = AppState(
      api: api,
      // 零延时，避免 Widget 测试等真实秒级节流。
      sleep: (Duration _) async {},
      runKeeper: keeper ?? const NoopRunKeeper(),
      keepAliveSettings: const NoopKeepAliveSettings(),
      windowShell: const NoopWindowShell(),
      update: noUpdateState(),
    );
    state.profile = const Profile(uid: '10086', name: '林知远', fid: '666');
    state.coursesState = LoadState.ready;
    state.courses = kDemoCourses;
    state.selectedCourse = kDemoCourses.first;
    state.chaptersState = LoadState.ready;
    state.chapters = kDemoChapters;
    return state;
  }

  /// 注入一次执行快照，让执行页有确定的进度与日志可渲染。
  AppState runningState({TaskPhase phase = TaskPhase.running}) {
    final AppState state = signedInState();
    state.run.seedForPreview(
      courseName: '高等数学（上）',
      chapterTitle: '第一章 函数与极限',
      progress: TaskProgress(
        phase: phase,
        current: phase == TaskPhase.running ? '1.2 数列的极限' : '',
        done: phase == TaskPhase.succeeded ? 3 : 1,
        total: 3,
        message: phase == TaskPhase.succeeded ? '完成 3 / 3' : '',
      ),
      course: kDemoCourses.first,
      chapter: kDemoChapters.first,
      logs: <TaskLog>[
        TaskLog('开始处理「第一章 函数与极限」，共 3 个视频任务点'),
        TaskLog('通过：1.1 映射与函数'),
        TaskLog('开始：1.2 数列的极限'),
      ],
    );
    return state;
  }

  group('课程工作台', () {
    testWidgets('未登录时给出连接入口与边界说明', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: AppState(api: FakeChaoxingApi())));

      expect(find.text('先连接你的学习通账号'), findsOneWidget);
      expect(find.text('连接账号'), findsOneWidget);
      expect(find.textContaining('请只用于你自己的账号'), findsOneWidget);
    });

    testWidgets('已登录渲染课程列表与汇总指标', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      expect(find.text('高等数学（上）'), findsOneWidget);
      expect(find.text('空间光环境基础'), findsOneWidget);
      expect(find.text('在修课程'), findsOneWidget);
      expect(find.text('已归档'), findsWidgets);
      expect(find.text('已连接'), findsOneWidget);
    });

    testWidgets('课程为空时显示空态而不是假数据', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState(courses: const <Course>[])));

      expect(find.text('这个账号还没有课程'), findsOneWidget);
      expect(find.text('高等数学（上）'), findsNothing);
    });

    testWidgets('读取失败显示错误原因与重试', (WidgetTester tester) async {
      final AppState state = signedInState();
      state.coursesState = LoadState.error;
      state.coursesError = '连接超时';
      await tester.pumpWidget(AutoChaoxingApp(state: state));

      expect(find.text('课程列表读取失败'), findsOneWidget);
      expect(find.text('连接超时'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('辅助页面', () {
    testWidgets('协议自检两行向量都通过', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('设置'));
      await tester.pump();
      await tester.tap(find.text('协议自检'));
      await tester.pump();

      expect(find.text('协议自检通过'), findsOneWidget);
      expect(find.text('通过'), findsNWidgets(2));
      expect(find.text('AES-CBC 登录加密'), findsOneWidget);
    });

    testWidgets('设置页收拢入口，运行约束在二级页且能返回', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('设置'));
      await tester.pump();

      // 一级设置页只有入口，不再平铺条款。
      expect(find.text('单账号串行'), findsNothing);
      expect(find.text('运行约束'), findsOneWidget);

      await tester.tap(find.text('运行约束'));
      await tester.pump();
      expect(find.text('单账号串行'), findsOneWidget);

      // 二级页有返回，且返回后回到设置列表。
      await tester.tap(find.byTooltip('返回设置'));
      await tester.pump();
      expect(find.text('单账号串行'), findsNothing);
      expect(find.text('协议自检'), findsOneWidget);
    });

    testWidgets('关于页给出仓库地址、版本与检查更新入口', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('设置'));
      await tester.pump();
      // 设置项变多后「关于」在 800x600 视口外，先滚到可见再点。
      final Finder about = find.text('关于');
      await tester.ensureVisible(about);
      await tester.pump();
      await tester.tap(about);
      await tester.pump();

      expect(find.text('Auto-Chaoxing'), findsOneWidget);
      expect(find.textContaining('github.com/SubmergeDQ/Auto-Chaoxing'), findsOneWidget);
      expect(find.text('当前版本 v0.4.1'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
    });

    testWidgets('设置里不再有那行免责文案', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));
      await tester.tap(find.text('设置'));
      await tester.pump();
      expect(find.textContaining('不代写作业'), findsNothing);
    });

    testWidgets('设置页断开连接后可以就地重连', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('设置'));
      await tester.pump();

      final Finder disconnect = find.text('断开连接');
      await tester.ensureVisible(disconnect);
      await tester.pump();
      await tester.tap(disconnect);
      await tester.pump();

      expect(find.text('断开连接'), findsNothing);
      expect(find.text('连接账号'), findsOneWidget);
      expect(find.text('未连接账号'), findsNWidgets(2), reason: '顶栏与账号卡片各一处');
    });

    testWidgets('自检结果切页回来还在', (WidgetTester tester) async {
      // 用 supported 的替身：Noop 下整块保活卡不渲染，测不到这条回归。
      final AppState state = signedInState(keeper: RunKeeperStub());
      // 真机上自检要跑 3 分钟，用户中间会去看课程；结果由 AppState 持有，
      // 挂在页面 State 上的话一切页就清零（这一条是回归）。
      state.probe.seedForPreview(
        phase: ProbePhase.done,
        ticks: 12,
        maxGap: const Duration(seconds: 15),
        elapsed: const Duration(minutes: 3),
      );

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      await tester.tap(find.text('设置'));
      await tester.pump();
      await tester.tap(find.text('协议自检'));
      await tester.pump();
      expect(find.text('计时连续'), findsOneWidget);

      await tester.tap(find.text('课程'));
      await tester.pump();
      await tester.tap(find.text('设置'));
      await tester.pump();
      await tester.tap(find.text('协议自检'));
      await tester.pump();

      expect(find.text('计时连续'), findsOneWidget);
      expect(find.text('未开始'), findsNothing, reason: '结果不该被重建抹掉');
    });

    testWidgets('保活页把通知与省电策略拆成两步，并就地申请权限', (WidgetTester tester) async {
      final KeepAliveSettingsStub keepAlive = KeepAliveSettingsStub();
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState(keepAlive: keepAlive)));

      await tester.tap(find.text('设置'));
      await tester.pump();
      await tester.tap(find.text('后台保活'));
      await tester.pumpAndSettle();

      expect(find.text('通知栏常驻'), findsOneWidget);
      expect(find.text('省电策略设为「无限制」'), findsOneWidget);
      expect(find.text('未开启'), findsNWidgets(2));

      await tester.tap(find.text('允许通知'));
      await tester.pumpAndSettle();

      expect(keepAlive.notificationRequests, 1);
      expect(find.text('已开启'), findsOneWidget);
      expect(find.text('未开启'), findsOneWidget);
    });

    testWidgets('窗口与托盘只在桌面端出现，改完立即落盘', (WidgetTester tester) async {
      final WindowShellStub shell = WindowShellStub();
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState(shell: shell)));

      await tester.tap(find.text('设置'));
      await tester.pump();
      final Finder entry = find.text('窗口与托盘');
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.text('每次询问'), findsOneWidget);

      await tester.tap(find.text('最小化到托盘'));
      await tester.pumpAndSettle();

      expect(shell.action, CloseAction.minimizeToTray);
    });
  });

  group('任务执行', () {
    testWidgets('没有执行记录时给出空态，并能回到课程工作台', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('执行'));
      await tester.pump();

      expect(find.text('还没有开始执行'), findsOneWidget);
      expect(find.text('去课程工作台'), findsOneWidget);

      await tester.tap(find.text('去课程工作台'));
      await tester.pump();

      expect(find.text('在修课程'), findsOneWidget);
    });

    testWidgets('运行中显示进度、当前任务点与停止入口', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: runningState()));

      await tester.tap(find.text('执行'));
      await tester.pump();

      expect(find.text('运行中'), findsOneWidget);
      expect(find.textContaining('已通过 1 / 3'), findsOneWidget);
      expect(find.textContaining('正在上报 1.2 数列的极限'), findsOneWidget);
      expect(find.text('停止执行'), findsOneWidget);
      expect(find.text('通过：1.1 映射与函数'), findsOneWidget);
      // 执行中的日志是本次运行的唯一现场证据，不给清空入口。
      expect(find.text('清空日志'), findsNothing);
    });

    testWidgets('需要人工时把停下原因摆在状态卡上', (WidgetTester tester) async {
      final AppState state = signedInState();
      state.run.seedForPreview(
        courseName: '高等数学（上）',
        chapterTitle: '第一章 函数与极限',
        progress: const TaskProgress(
          phase: TaskPhase.needsAttention,
          done: 1,
          total: 2,
          message: '登录已失效，请重新连接账号后再继续',
        ),
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
        logs: <TaskLog>[
          TaskLog('登录已失效，请重新连接账号后再继续', level: 'error'),
        ],
      );
      await tester.pumpWidget(AutoChaoxingApp(state: state));

      await tester.tap(find.text('执行'));
      await tester.pump();

      expect(find.text('需要人工'), findsOneWidget);
      expect(find.textContaining('登录已失效'), findsWidgets);
      expect(find.textContaining('不会自动重试'), findsOneWidget);
      expect(find.text('再次执行'), findsOneWidget);
      expect(find.text('停止执行'), findsNothing);
    });

    testWidgets('已完成的执行给出再次执行，不再显示停止', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: runningState(phase: TaskPhase.succeeded)));

      await tester.tap(find.text('执行'));
      await tester.pump();

      expect(find.text('本次执行完成'), findsOneWidget);
      expect(find.text('再次执行'), findsOneWidget);
      expect(find.text('停止执行'), findsNothing);
    });

    testWidgets('章节展开后有执行入口，确认前不发起执行', (WidgetTester tester) async {
      final AppState state = courseSelectedState();
      await state.loadPoints(kDemoChapters.first);

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      // 窄屏测试视口：先选课程进入章节下钻页，再展开章节。
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('第一章 函数与极限'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('执行本章视频'), findsOneWidget);
      expect(find.textContaining('2 个视频任务点 · 耗时与视频总长相近'), findsOneWidget);
      // 混排章节要说清非视频任务点不归本客户端管，否则用户以为一键做完。
      expect(find.textContaining('另有 2 个非视频任务点'), findsOneWidget);

      final Finder runButton = find.text('执行本章视频');
      await tester.ensureVisible(runButton);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(runButton);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('开始执行本章视频'), findsOneWidget);
      expect(find.textContaining('人脸抽检'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(state.run.hasRun, isFalse);
      expect(find.text('开始执行本章视频'), findsNothing);
    });

    testWidgets('章节面板提供整门课入口，确认前不发起执行', (WidgetTester tester) async {
      final AppState state = courseSelectedState();
      final FakeChaoxingApi api = state.api as FakeChaoxingApi;

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      // 窄屏测试视口：先选课程进入章节下钻页；整门课入口在面板头部，不需要展开章节。
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final Finder runAll = find.text('执行整门课');
      expect(runAll, findsOneWidget);

      await tester.tap(runAll);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('开始执行整门课'), findsOneWidget);
      expect(find.textContaining('全部 4 章'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(state.run.hasRun, isFalse);
      expect(api.cardsCalls, 0);
    });

    testWidgets('课程面板有签到入口，签到成功后标为已签到', (WidgetTester tester) async {
      final AppState state = courseSelectedState();
      final FakeChaoxingApi api = state.api as FakeChaoxingApi;
      final DateTime now = DateTime.now();
      api.signActivities = <SignActivity>[
        SignActivity(
          activeId: 'a1',
          name: '第 3 次课签到',
          type: 2,
          status: 1,
          startAt: now.subtract(const Duration(minutes: 5)),
          endAt: now.add(const Duration(minutes: 10)),
        ),
      ];

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final Finder signEntry = find.text('签到');
      await tester.ensureVisible(signEntry);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(signEntry);
      await tester.pumpAndSettle();

      expect(find.text('第 3 次课签到'), findsOneWidget);
      expect(find.text('进行中'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '签到'));
      await tester.pumpAndSettle();

      expect(api.signedActiveIds, <String>['a1']);
      expect(find.text('已签到'), findsWidgets);
      expect(find.text('进行中'), findsNothing);
    });

    testWidgets('没有签到活动时给出空态而不是空白页', (WidgetTester tester) async {
      final AppState state = courseSelectedState();

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final Finder signEntry = find.text('签到');
      await tester.ensureVisible(signEntry);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(signEntry);
      await tester.pumpAndSettle();

      expect(find.text('这门课暂时没有签到活动'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
    });

    testWidgets('支持保活的平台在签到页提供后台监听开关', (WidgetTester tester) async {
      final RunKeeperStub keeper = RunKeeperStub();
      final AppState state = courseSelectedState(keeper: keeper);

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final Finder signEntry = find.text('签到');
      await tester.ensureVisible(signEntry);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(signEntry);
      await tester.pumpAndSettle();

      expect(find.text('后台监听签到'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(keeper.beginCalls, 1);
      expect(state.sign.watching, isTrue);

      // 退出页面：监听保持，轮询不停。
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state.sign.watching, isTrue);
      expect(keeper.endCalls, 0);

      // 测试收尾：停掉监听计时器，避免 pending timer 让用例失败。
      state.sign.stopWatching();
      await tester.pump();
    });

    testWidgets('课程面板有作业入口，列表区分已交与未交', (WidgetTester tester) async {
      final AppState state = courseSelectedState();
      final FakeChaoxingApi api = state.api as FakeChaoxingApi;
      api.homeworks = <HomeworkItem>[
        HomeworkItem(
          workId: '1',
          name: '第一章作业',
          completed: true,
          endAt: DateTime.now().add(const Duration(days: 3)),
        ),
        const HomeworkItem(workId: '2', name: '第二章作业', completed: false),
        const HomeworkItem(workId: '3', name: '第三章作业'),
      ];

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final Finder homeworkEntry = find.text('作业');
      await tester.ensureVisible(homeworkEntry);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(homeworkEntry);
      await tester.pumpAndSettle();

      expect(find.text('第一章作业'), findsOneWidget);
      expect(find.text('已交'), findsOneWidget);
      expect(find.text('未交'), findsOneWidget);
      // 平台没给状态字段时显示「状态未知」，不能猜成未交。
      expect(find.text('状态未知'), findsOneWidget);
      expect(find.text('打开作答页'), findsNWidgets(3));

      // 免责说明在列表底部，测试视口外，滚到底再看。
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('不代提交作业'), findsOneWidget);
    });

    testWidgets('设置页可以打开账号切换并列出本机账号', (WidgetTester tester) async {
      final FakeSessionJar store = FakeSessionJar();
      final FakeChaoxingApi api = FakeChaoxingApi()
        ..profilesByUid['10086'] =
            const Profile(uid: '10086', name: '林知远', fid: '666', school: '示例大学')
        ..profilesByUid['20001'] =
            const Profile(uid: '20001', name: '周敏', fid: '666', school: '另一所大学');
      final AppState state = AppState(
        api: api,
        session: store,
        sleep: (Duration _) async {},
        runKeeper: const NoopRunKeeper(),
        keepAliveSettings: const NoopKeepAliveSettings(),
        windowShell: const NoopWindowShell(),
        update: noUpdateState(),
      );
      await state.signIn('13800000000', 'pw-a');
      api.loginProfile = api.profilesByUid['20001'];
      await state.signIn('13900000000', 'pw-b');

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      await tester.tap(find.text('设置'));
      await tester.pump();

      expect(find.text('切换账号'), findsOneWidget);
      await tester.tap(find.text('切换账号'));
      await tester.pumpAndSettle();

      expect(find.text('林知远'), findsOneWidget);
      expect(find.text('周敏'), findsWidgets);
      expect(find.text('当前'), findsOneWidget);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    });

    testWidgets('顶栏显示头像，点击昵称进入设置页', (WidgetTester tester) async {
      final AppState state = courseSelectedState();
      state.avatarBytes = kTinyPng;

      await tester.pumpWidget(AutoChaoxingApp(state: state));

      // 头像用 CircleAvatar 渲染；取不到时也走 CircleAvatar（首字回退）。
      expect(find.byType(CircleAvatar), findsOneWidget);

      await tester.tap(find.byTooltip('账号与设置'));
      await tester.pumpAndSettle();

      expect(find.text('断开连接'), findsOneWidget);
      expect(find.text('账号'), findsOneWidget);
    });

    testWidgets('重跑前说明哪些已通过会跳过、哪些从中间继续', (WidgetTester tester) async {
      final AppState state = courseSelectedState(
        points: const <TaskPoint>[
          TaskPoint(
            type: 'video',
            jobId: 'j-101',
            name: '1.1 映射与函数',
            objectId: 'o-101',
            passed: true,
          ),
          TaskPoint(
            type: 'video',
            jobId: 'j-103',
            name: '1.2 数列的极限',
            objectId: 'o-103',
            attDuration: '60',
          ),
          TaskPoint(type: 'document', jobId: 'j-102', name: '第一章课程讲义.pdf'),
        ],
      );
      await state.loadPoints(kDemoChapters.first);

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('第一章 函数与极限'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('2 个视频任务点 · 1 个平台已通过将跳过，1 个从中间继续'),
        findsOneWidget,
        reason: '任务点没动时用户要能查到这里说了会跳过',
      );
    });

    testWidgets('结束时可以复制脱敏日志，运行中不提供', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: runningState(phase: TaskPhase.succeeded)));
      await tester.tap(find.text('执行'));
      await tester.pump();

      expect(find.text('复制日志'), findsOneWidget);

      await tester.tap(find.text('复制日志'));
      await tester.pump();
      expect(find.text('日志已复制，手机号与令牌已隐去'), findsOneWidget);
    });

    testWidgets('运行中不给复制与清空，只留停止', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: runningState()));
      await tester.tap(find.text('执行'));
      await tester.pump();

      expect(find.text('复制日志'), findsNothing);
      expect(find.text('清空日志'), findsNothing);
      expect(find.text('停止执行'), findsOneWidget);
    });

    testWidgets('确认执行后切到任务执行页并留下日志', (WidgetTester tester) async {
      final AppState state = courseSelectedState();
      await state.loadPoints(kDemoChapters.first);

      await tester.pumpWidget(AutoChaoxingApp(state: state));
      // 窄屏测试视口：先选课程进入章节下钻页，再展开章节。
      await tester.tap(find.text('高等数学（上）'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('第一章 函数与极限'));
      await tester.pump(const Duration(milliseconds: 300));

      final Finder runButton = find.text('执行本章视频');
      await tester.ensureVisible(runButton);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(runButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('开始执行'));
      await tester.pump();
      // 等确认框关闭、下钻页退场动画走完，再看执行页。
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(state.run.hasRun, isTrue);
      expect(find.text('第一章 函数与极限'), findsOneWidget, reason: '状态卡显示本次章节');
      expect(find.text('执行日志'), findsOneWidget);
      expect(find.text('本次执行完成'), findsOneWidget);
    });
  });
}

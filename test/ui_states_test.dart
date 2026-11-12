import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:auto_chaoxing/main.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  AppState signedInState({List<Course> courses = kDemoCourses}) {
    final AppState state = AppState(api: FakeChaoxingApi(courses: courses));
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

  AppState courseSelectedState() {
    final AppState state = AppState(
      api: FakeChaoxingApi(
        courses: kDemoCourses,
        chapters: kDemoChapters,
        points: kDemoPoints,
      ),
      // 零延时，避免 Widget 测试等真实秒级节流。
      sleep: (Duration _) async {},
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

      await tester.tap(find.text('自检'));
      await tester.pump();

      expect(find.text('协议自检通过'), findsOneWidget);
      expect(find.text('通过'), findsNWidgets(2));
      expect(find.text('AES-CBC 登录加密'), findsOneWidget);
    });

    testWidgets('设置页展示运行约束与断开连接', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('设置'));
      await tester.pump();

      expect(find.text('单账号串行'), findsOneWidget);
      expect(find.text('断开连接'), findsOneWidget);

      final Finder disconnect = find.text('断开连接');
      await tester.ensureVisible(disconnect);
      await tester.pump();
      await tester.tap(disconnect);
      await tester.pump();

      expect(find.text('断开连接'), findsNothing);
      expect(find.text('未连接账号'), findsNWidgets(2), reason: '顶栏与账号卡片各一处');
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
      expect(find.text('2 个视频任务点 · 耗时与视频总长相近'), findsOneWidget);

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

import 'dart:async';

import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:auto_chaoxing/platform/platform_services.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:auto_chaoxing/state/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_run_keeper.dart';

Future<void> _noSleep(Duration _) async {}

Future<void> _waitFor(bool Function() condition) async {
  for (int i = 0; i < 50 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AppState _stateWith(FakeChaoxingApi api, {RunKeeperStub? keeper}) {
  final AppState state = AppState(
    api: api,
    sleep: _noSleep,
    runKeeper: keeper ?? const NoopRunKeeper(),
  );
  state.profile = api.demoProfile;
  state.coursesState = LoadState.ready;
  state.courses = kDemoCourses;
  state.selectedCourse = kDemoCourses.first;
  state.chaptersState = LoadState.ready;
  state.chapters = kDemoChapters;
  return state;
}

void main() {
  group('RunController', () {
    test('执行整章后进入成功终态，并记录进度与日志', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final AppState state = _stateWith(api);

      expect(state.run.busy, isFalse);
      expect(state.run.hasRun, isFalse);

      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);

      expect(state.run.phase, TaskPhase.succeeded);
      expect(state.run.busy, isFalse);
      expect(state.run.hasRun, isTrue);
      expect(state.run.startedAt, isNotNull);
      expect(state.run.finishedAt, isNotNull);
      expect(state.run.progress.done, 2);
      expect(state.run.progress.total, 2);
      expect(state.run.courseName, '高等数学（上）');
      expect(state.run.chapterTitle, '第一章 函数与极限');
      expect(state.run.logs, isNotEmpty);
      expect(state.run.logs.last.message, contains('2 / 2 个任务点已通过'));
    });

    test('执行中再点开始会被忽略，保持单账号串行', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..reportGate = Completer<void>();
      final AppState state = _stateWith(api);

      final Future<void> running =
          state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);
      await _waitFor(() => api.reportCalls >= 1);

      expect(state.run.busy, isTrue);

      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters[1]);
      expect(api.reportCalls, 1, reason: '第二个任务不应被启动');
      expect(state.run.chapterTitle, '第一章 函数与极限');

      api.reportGate!.complete();
      await running;
      expect(state.run.phase, TaskPhase.succeeded);
    });

    test('停止后进入 stopped，日志说明已停下', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..reportGate = Completer<void>();
      final AppState state = _stateWith(api);

      final Future<void> running =
          state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);
      await _waitFor(() => api.reportCalls >= 1);

      state.run.stop();
      api.reportGate!.complete();
      await running;

      expect(state.run.phase, TaskPhase.stopped);
      expect(state.run.busy, isFalse);
      expect(
        state.run.logs.any((TaskLog l) => l.message.contains('已停止')),
        isTrue,
      );
    });

    test('章节未开放时进入需要人工，且不留下误导性的运行中状态', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        points: kDemoPoints,
        cardsErrorCode: 'locked',
      );
      final AppState state = _stateWith(api);

      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);

      expect(state.run.phase, TaskPhase.needsAttention);
      expect(state.run.progress.message, contains('章节未开放'));
      expect(state.run.busy, isFalse);
      expect(api.reportCalls, 0);
    });

    test('断开连接会清空执行会话与日志', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final AppState state = _stateWith(api);
      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);
      expect(state.run.logs, isNotEmpty);

      await state.signOut();

      expect(state.run.phase, TaskPhase.idle);
      expect(state.run.hasRun, isFalse);
      expect(state.run.logs, isEmpty);
      expect(state.run.chapterTitle, isEmpty);
    });

    test('再次执行会重新上报本章进度', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final AppState state = _stateWith(api);

      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);
      final int firstRunCalls = api.reportCalls;
      expect(state.run.canRerun, isTrue);

      await state.run.rerun();

      expect(api.reportCalls, firstRunCalls * 2);
      expect(state.run.phase, TaskPhase.succeeded);
    });

    test('日志按上限裁剪，长时间运行不会无限增长', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..videoSeconds = 120000; // 每个视频 2001 次上报，必然超出日志上限
      final AppState state = _stateWith(api);

      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);

      expect(state.run.logs.length, lessThanOrEqualTo(RunController.maxLogs));
      expect(state.run.logs.length, RunController.maxLogs);
    });
  });

  group('整门课批量执行', () {
    test('按章节串行跑完，跳过无视频章节并给出汇总', () async {
      final FakeChaoxingApi api = FakeChaoxingApi()
        ..pointsByChapter['510001'] = kDemoPoints
        ..pointsByChapter['510002'] = const <TaskPoint>[]
        ..pointsByChapter['510003'] = const <TaskPoint>[
          TaskPoint(type: 'document', jobId: 'j-201', name: '讲义.pdf'),
        ]
        ..pointsByChapter['510004'] = kDemoPoints;
      final AppState state = _stateWith(api);

      await state.run.startCourse(course: kDemoCourses.first, chapters: kDemoChapters);

      expect(state.run.phase, TaskPhase.succeeded);
      expect(state.run.batchMode, isTrue);
      expect(state.run.batchTotal, 4);
      expect(state.run.batchDone, 4);
      expect(api.cardsCalls, 4, reason: '四章都要读卡片');
      expect(state.run.chapterTitle, '整门课（4 章）');
      // 两章有视频，另外两章分别是「没有任务点」和「只有文档」。
      expect(state.run.progress.message, contains('2 章完成'));
      expect(state.run.progress.message, contains('2 章无视频跳过'));
      expect(
        state.run.logs.any((TaskLog l) => l.message.contains('第 4/4 章')),
        isTrue,
        reason: '日志里要能看出走到哪一章',
      );
    });

    test('遇到需要人工的章节立即停止，不再进入下一章', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..cardsErrorCode = 'locked';
      final AppState state = _stateWith(api);

      await state.run.startCourse(course: kDemoCourses.first, chapters: kDemoChapters);

      expect(state.run.phase, TaskPhase.needsAttention);
      expect(api.cardsCalls, 1, reason: '第一章就锁定，后续章节不再请求');
      expect(state.run.batchDone, 1);
      expect(state.run.progress.message, contains('第一章 函数与极限'));
    });

    test('中途停止后不再进入下一章', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..reportGate = Completer<void>();
      final AppState state = _stateWith(api);

      final Future<void> running =
          state.run.startCourse(course: kDemoCourses.first, chapters: kDemoChapters);
      await _waitFor(() => api.reportCalls >= 1);

      state.run.stop();
      api.reportGate!.complete();
      api.reportGate = null;
      await running;

      expect(state.run.phase, TaskPhase.stopped);
      expect(api.cardsCalls, 1, reason: '停止后不该再读下一章的卡片');
      expect(state.run.batchDone, 1);
      expect(state.run.progress.message, contains('已处理 1 / 4 章'));
    });

    test('再次执行沿用整门课范围', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final AppState state = _stateWith(api);

      await state.run.startCourse(course: kDemoCourses.first, chapters: kDemoChapters);
      final int firstRound = api.cardsCalls;

      await state.run.rerun();

      expect(api.cardsCalls, firstRound * 2);
      expect(state.run.batchTotal, 4);
      expect(state.run.phase, TaskPhase.succeeded);
    });
  });

  group('后台保活', () {
    test('执行期间起保活，结束后换成结果通知', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final RunKeeperStub keeper = RunKeeperStub();
      final AppState state = _stateWith(api, keeper: keeper);

      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);

      expect(keeper.beginCalls, 1);
      // 标题要能让人在通知栏认出是哪一章。
      expect(keeper.beginTitle, contains('第一章 函数与极限'));
      // 进度确实在往通知上走，不是起了一次就再也不更新。
      expect(keeper.notices.length, greaterThan(1));
      expect(keeper.notices.any((String s) => s.contains('已通过')), isTrue);

      expect(keeper.finishCalls, 1);
      expect(keeper.finishedTitle, contains('本次执行完成'));
      expect(keeper.finishedBody, '已通过 2 / 2');
      expect(keeper.endCalls, 0);
    });

    test('保活起不来时记一条告警，执行照常完成', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final RunKeeperStub keeper = RunKeeperStub(beginResult: false);
      final AppState state = _stateWith(api, keeper: keeper);

      await state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);

      expect(state.run.phase, TaskPhase.succeeded);
      expect(
        state.run.logs.any((TaskLog l) => l.level == 'warn' && l.message.contains('后台保活未启用')),
        isTrue,
      );
      // 没起来就不该跳过去刷通知或发结果。
      expect(keeper.updateCalls, 0);
      expect(keeper.finishCalls, 0);
      expect(keeper.endCalls, 0);
    });

    test('通知栏点停止等价于页面上点停止执行', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final RunKeeperStub keeper = RunKeeperStub();
      final AppState state = _stateWith(api, keeper: keeper);
      // 卡住第一次上报，好在「执行中」这个窗口里点停止。
      api.reportGate = Completer<void>();

      final Future<void> running =
          state.run.start(course: kDemoCourses.first, chapter: kDemoChapters.first);
      await _waitFor(() => api.reportCalls > 0);
      expect(state.run.busy, isTrue);

      keeper.tapStopOnNotification();
      await _waitFor(() => state.run.progress.message == '正在停止…');
      expect(state.run.progress.message, '正在停止…');

      api.reportGate!.complete();
      api.reportGate = null;
      await running;

      expect(state.run.phase, TaskPhase.stopped);
      // 用户主动叫停不是失败，不该发「本次执行完成」。
      expect(keeper.finishedTitle, contains('已停止'));
    });
  });
}

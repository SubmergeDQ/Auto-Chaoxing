import 'dart:async';

import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:auto_chaoxing/state/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

Future<void> _noSleep(Duration _) async {}

Future<void> _waitFor(bool Function() condition) async {
  for (int i = 0; i < 50 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AppState _stateWith(FakeChaoxingApi api) {
  final AppState state = AppState(api: api, sleep: _noSleep);
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

      state.signOut();

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
}

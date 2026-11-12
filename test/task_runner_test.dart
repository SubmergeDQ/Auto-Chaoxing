import 'dart:async';

import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

/// 注入零延时，用例不必等真实的秒级节流。
Future<void> _noSleep(Duration _) async {}

Future<void> _waitFor(bool Function() condition) async {
  for (int i = 0; i < 50 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('TaskRunner', () {
    test('逐点上报直到平台判定通过，结束后给出成功终态', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      final List<TaskProgress> progress = <TaskProgress>[];
      final List<TaskLog> logs = <TaskLog>[];

      final TaskRunner runner = TaskRunner(
        api,
        sleep: _noSleep,
        onProgress: progress.add,
        onLog: logs.add,
      );
      final VideoRunnerResult r = await runner.runChapterVideos(
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
      );

      expect(r.phase, TaskPhase.succeeded);
      expect(r.completed, <String>['1.1 映射与函数', '1.2 数列的极限']);
      expect(r.failed, isEmpty);
      // 120s / 60s 步长 = 0/60/120 三次上报，两个视频共 6 次。
      expect(api.reportCalls, 6);
      expect(progress.last.phase, TaskPhase.succeeded);
      expect(progress.last.done, 2);
      expect(progress.last.total, 2);
      expect(logs.any((TaskLog l) => l.message.contains('开始处理')), isTrue);
      expect(logs.any((TaskLog l) => l.message == '通过：1.1 映射与函数'), isTrue);
      expect(logs.last.message, contains('2 / 2 个任务点已通过'));
    });

    test('到结尾仍未通过的任务点计入失败，不影响其他任务点', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints);
      api.neverPass.add('o-103');
      final List<TaskLog> logs = <TaskLog>[];

      final TaskRunner runner = TaskRunner(api, sleep: _noSleep, onLog: logs.add);
      final VideoRunnerResult r = await runner.runChapterVideos(
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
      );

      expect(r.phase, TaskPhase.failed);
      expect(r.completed, <String>['1.1 映射与函数']);
      expect(r.failed, <String>['1.2 数列的极限']);
      expect(
        logs.any((TaskLog l) => l.level == 'warn' && l.message.contains('未通过：1.2 数列的极限')),
        isTrue,
      );
    });

    test('章节未开放归为需要人工，且不发起任何上报', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        points: kDemoPoints,
        cardsErrorCode: 'locked',
      );

      final TaskRunner runner = TaskRunner(api, sleep: _noSleep);
      final VideoRunnerResult r = await runner.runChapterVideos(
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
      );

      expect(r.phase, TaskPhase.needsAttention);
      expect(r.message, contains('章节未开放'));
      expect(api.reportCalls, 0);
      expect(api.statusCalls, 0);
    });

    test('上报返回登录失效时立即终止，并说明要重新连接', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..authExpiredOnReport = true;
      final List<TaskLog> logs = <TaskLog>[];

      final TaskRunner runner = TaskRunner(api, sleep: _noSleep, onLog: logs.add);
      final VideoRunnerResult r = await runner.runChapterVideos(
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
      );

      expect(r.phase, TaskPhase.needsAttention);
      expect(r.message, contains('重新连接'));
      expect(api.reportCalls, 1, reason: '登录失效后不该继续尝试后面的任务点');
      expect(logs.last.level, 'error');
    });

    test('中途登录失效时停下，已完成的任务点保留在结果里', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..authExpiredAfterReports = 3;

      final TaskRunner runner = TaskRunner(api, sleep: _noSleep);
      final VideoRunnerResult r = await runner.runChapterVideos(
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
      );

      expect(r.phase, TaskPhase.needsAttention);
      expect(r.completed, <String>['1.1 映射与函数']);
      expect(api.reportCalls, 4);
    });

    test('主动停止以 stopped 收尾，不计为失败', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(points: kDemoPoints)
        ..reportGate = Completer<void>();

      final TaskRunner runner = TaskRunner(api, sleep: _noSleep);
      final Future<VideoRunnerResult> pending = runner.runChapterVideos(
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
      );

      await _waitFor(() => api.reportCalls >= 1);
      runner.requestStop();
      api.reportGate!.complete();

      final VideoRunnerResult r = await pending;
      expect(r.phase, TaskPhase.stopped);
      expect(r.failed, isEmpty);
      expect(r.message, contains('从断点继续'));
    });

    test('本章没有视频任务点时直接成功，不请求视频状态', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        points: const <TaskPoint>[
          TaskPoint(type: 'document', jobId: 'j-1', name: '讲义.pdf'),
          TaskPoint(type: 'workid', jobId: 'j-2', name: '章节作业'),
        ],
      );

      final TaskRunner runner = TaskRunner(api, sleep: _noSleep);
      final VideoRunnerResult r = await runner.runChapterVideos(
        course: kDemoCourses.first,
        chapter: kDemoChapters.first,
      );

      expect(r.phase, TaskPhase.succeeded);
      expect(r.message, '本章没有视频任务点');
      expect(api.statusCalls, 0);
    });
  });
}

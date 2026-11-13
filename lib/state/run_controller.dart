// 执行会话：持有 TaskRunner、进度与实时日志，把变化汇报给 AppState。
// 只做会话状态，不参与界面；界面通过 AppState 的 Listenable 刷新。
import 'dart:async';

import '../core/chaoxing_api.dart';
import '../core/models.dart';
import '../core/task_runner.dart';
import '../platform/platform_services.dart';

class RunController {
  RunController({
    required ChaoxingApi api,
    required void Function() onChanged,
    Future<void> Function(Duration)? sleep,
    RunKeeper keeper = const NoopRunKeeper(),
  })  : _api = api,
        _onChanged = onChanged,
        _sleep = sleep,
        _keeper = keeper {
    // 通知栏的「停止」与页面上的「停止执行」是同一个动作，走同一条路径。
    _stopSub = _keeper.stopRequests.listen((void _) => stop());
  }

  /// 日志上限：长时间运行时只保留最近这些条，避免内存与渲染越跑越重。
  static const int maxLogs = 400;

  final ChaoxingApi _api;
  final void Function() _onChanged;
  final Future<void> Function(Duration)? _sleep;
  final RunKeeper _keeper;

  final List<TaskLog> logs = <TaskLog>[];

  StreamSubscription<void>? _stopSub;

  /// 因为上限被丢掉的日志条数。导出时要说清「这份日志不是全部」。
  int droppedLogs = 0;

  TaskProgress progress = const TaskProgress(phase: TaskPhase.idle);
  String courseName = '';
  String chapterTitle = '';
  DateTime? startedAt;
  DateTime? finishedAt;

  TaskRunner? _runner;
  Course? _lastCourse;
  List<Chapter> _lastChapters = const <Chapter>[];

  /// 整门课批量执行：batchTotal 为 0 表示当前（或上一次）是单章执行。
  int batchTotal = 0;
  int batchDone = 0;

  bool get batchMode => batchTotal > 0;

  /// 保活是否真的起来了。只在 true 时刷通知，避免对没起的服务空喊。
  bool _keeping = false;

  /// 上一次推给通知的正文，用来去重：进度没变就不必刷。
  String _noticeBody = '';

  /// 会话令牌：reset 后旧 Runner 的回调仍可能到达，用令牌把它们丢掉。
  int _session = 0;
  bool _disposed = false;

  TaskPhase get phase => progress.phase;

  /// 会话正在进行（含章与章之间的空档）。只看 phase 的话，上一章刚结束、
  /// 下一章还没开始的瞬间 busy 会变 false，用户可以再点一次开始。
  bool _active = false;

  /// 正在读取或执行：此时不允许再起第二个任务（单账号串行）。
  bool get busy => _active || phase == TaskPhase.preparing || phase == TaskPhase.running;

  bool get hasRun => startedAt != null;

  bool get canRerun => !busy && _lastCourse != null && _lastChapters.isNotEmpty;

  /// 当前是否处在「熄屏也继续跑」的状态，供界面如实说明。
  bool get keeping => _keeping;

  /// 批次级停止标记：用户可能正好点在「上一章结束、下一章未开始」的空档，
  /// 此时没有 runner 可停，只能靠这个标记让循环不再往下走。
  bool _stopBatch = false;

  Future<void> start({required Course course, required Chapter chapter}) async {
    if (busy || _disposed) return;
    await _runSession(
      course: course,
      chapters: <Chapter>[chapter],
      batch: false,
    );
  }

  /// 整门课：按章节顺序串行跑，无视频的章直接跳过。
  ///
  /// 与单章一样，遇到 locked / 登录失效 / 人脸抽检立刻停：后面的章节依赖
  /// 前面的完成状态，硬跑只会连续失败，还会把「需要人工」埋进一长串日志里。
  Future<void> startCourse({
    required Course course,
    required List<Chapter> chapters,
  }) async {
    if (busy || _disposed || chapters.isEmpty) return;
    await _runSession(
      course: course,
      chapters: chapters,
      batch: true,
    );
  }

  Future<void> _runSession({
    required Course course,
    required List<Chapter> chapters,
    required bool batch,
  }) async {
    if (busy || _disposed || chapters.isEmpty) return;

    // 会话令牌在这里就取：保活是异步的，等它回来期间 reset/新会话可能已经发生。
    final int session = ++_session;
    _active = true;
    try {
      await _runSessionInner(
        course: course,
        chapters: chapters,
        batch: batch,
        session: session,
      );
    } finally {
      // 只有仍然是当前会话时才收尾：旧会话的 finally 不能把新会话的活跃状态抹掉。
      if (session == _session) {
        _active = false;
        _onChanged();
      }
    }
  }

  Future<void> _runSessionInner({
    required Course course,
    required List<Chapter> chapters,
    required bool batch,
    required int session,
  }) async {
    _lastCourse = course;
    _lastChapters = List<Chapter>.unmodifiable(chapters);
    _stopBatch = false;
    courseName = course.name;
    chapterTitle = batch ? '整门课（${chapters.length} 章）' : chapters.first.title;
    logs.clear();
    droppedLogs = 0;
    startedAt = DateTime.now();
    finishedAt = null;
    batchTotal = batch ? chapters.length : 0;
    batchDone = 0;
    progress = const TaskProgress(phase: TaskPhase.preparing, message: '准备中…');
    _onChanged();

    // 先起保活再发第一个请求：首个请求之后就要等 60 秒，晚起就白等一段。
    await _beginKeeping();
    if (_disposed || session != _session) return;

    final _BatchTally tally = _BatchTally();
    int processed = 0;
    TaskPhase finalPhase = TaskPhase.succeeded;
    String finalMessage = '';

    if (batch) {
      _appendLog(TaskLog('开始整门课：共 ${chapters.length} 章，单章串行处理'));
    }

    for (int i = 0; i < chapters.length; i++) {
      if (session != _session || _disposed) return;
      if (_stopBatch) {
        finalPhase = TaskPhase.stopped;
        finalMessage = '已停止：已处理 $processed / ${chapters.length} 章';
        break;
      }

      final Chapter chapter = chapters[i];
      chapterTitle = chapter.title;
      if (batch) {
        batchDone = i;
        _appendLog(TaskLog('— 第 ${i + 1}/${chapters.length} 章：${chapter.title}'));
      }
      _syncNotice();
      progress = const TaskProgress(phase: TaskPhase.preparing, message: '准备中…');
      _onChanged();

      final TaskRunner runner = TaskRunner(
        _api,
        sleep: _sleep,
        onProgress: (TaskProgress p) {
          if (session != _session || _disposed) return;
          progress = p;
          _syncNotice();
          _onChanged();
        },
        onLog: (TaskLog log) {
          if (session != _session || _disposed) return;
          _appendLog(log);
        },
      );
      _runner = runner;

      final VideoRunnerResult result = await runner.runChapterVideos(
        course: course,
        chapter: chapter,
      );
      if (session != _session || _disposed) return;
      _runner = null;
      processed++;
      batchDone = processed;

      switch (result.phase) {
        case TaskPhase.succeeded:
          if (result.completed.isEmpty && result.skipped.isEmpty) {
            // 整章没有视频任务点：不算失败，单独计数，汇总时说清楚。
            tally.empty++;
          } else {
            tally.ok++;
          }
        case TaskPhase.failed:
          tally.failed++;
        case TaskPhase.stopped:
          finalPhase = TaskPhase.stopped;
          finalMessage = '已停止：已处理 $processed / ${chapters.length} 章';
        case TaskPhase.needsAttention:
          finalPhase = TaskPhase.needsAttention;
          finalMessage = '「${chapter.title}」需要人工处理：${result.message}';
        case TaskPhase.preparing:
        case TaskPhase.running:
        case TaskPhase.idle:
          break;
      }

      if (finalPhase == TaskPhase.needsAttention || finalPhase == TaskPhase.stopped) {
        break;
      }
    }

    if (session != _session || _disposed) return;
    finishedAt = DateTime.now();

    if (batch) {
      chapterTitle = '整门课（${chapters.length} 章）';
      // 人工介入与主动停止已经有更具体的原因，不再用批次汇总盖掉它。
      if (finalPhase == TaskPhase.succeeded || finalPhase == TaskPhase.failed) {
        finalPhase = tally.failed > 0 ? TaskPhase.failed : TaskPhase.succeeded;
        finalMessage = _batchSummary(tally, chapters.length);
      }
      _appendLog(
        TaskLog(
          '结束：$finalMessage',
          level: finalPhase == TaskPhase.failed ? 'warn' : 'info',
        ),
      );
    }

    progress = progress.copyWith(phase: finalPhase, message: finalMessage);
    _onChanged();
    await _finishKeeping(finalPhase);
  }

  String _batchSummary(_BatchTally tally, int total) {
    final List<String> parts = <String>[
      '${tally.ok} 章完成',
      if (tally.empty > 0) '${tally.empty} 章无视频跳过',
      if (tally.failed > 0) '${tally.failed} 章有未通过任务点',
    ];
    return '${parts.join('，')}（共 $total 章）';
  }

  void clearLogs() {
    if (logs.isEmpty) return;
    logs.clear();
    droppedLogs = 0;
    _onChanged();
  }

  /// 用上一次的课程与章节再跑一遍；批量过的仍然是整门课。
  /// 已经通过的任务点平台会直接判过。
  Future<void> rerun() async {
    final Course? course = _lastCourse;
    final List<Chapter> chapters = _lastChapters;
    if (course == null || chapters.isEmpty || busy) return;
    await _runSession(
      course: course,
      chapters: chapters,
      batch: batchMode,
    );
  }

  void stop() {
    _stopBatch = true;
    final TaskRunner? runner = _runner;
    runner?.requestStop();
    if (runner != null) {
      progress = progress.copyWith(message: '正在停止…');
      _syncNotice();
      _onChanged();
    }
  }

  /// 断开账号或切换身份时清空会话，避免旧的执行状态挂到新账号上。
  void reset() {
    _session++;
    _active = false;
    _runner?.requestStop();
    _runner = null;
    _lastCourse = null;
    _lastChapters = const <Chapter>[];
    _stopBatch = false;
    batchTotal = 0;
    batchDone = 0;
    logs.clear();
    droppedLogs = 0;
    progress = const TaskProgress(phase: TaskPhase.idle);
    courseName = '';
    chapterTitle = '';
    startedAt = null;
    finishedAt = null;
    unawaited(_endKeeping());
    _onChanged();
  }

  void dispose() {
    _disposed = true;
    _session++;
    _active = false;
    _runner?.requestStop();
    _stopSub?.cancel();
    _stopSub = null;
    unawaited(_endKeeping());
  }

  // ——— 保活 ———

  void _appendLog(TaskLog log) {
    logs.add(log);
    if (logs.length > maxLogs) {
      final int cut = logs.length - maxLogs;
      logs.removeRange(0, cut);
      droppedLogs += cut;
    }
    _onChanged();
  }

  Future<void> _beginKeeping() async {
    if (!_keeper.supported) return;
    // 没有通知权限照样能保活，但用户既看不到进度也点不到「停止」，所以先要一次。
    final bool notifyOk = await _keeper.ensureNotificationPermission();
    final bool ok = await _keeper.begin(
      title: '执行中：${chapterTitle.isEmpty ? '课程任务' : chapterTitle}',
      body: '准备中…',
    );
    if (_disposed) {
      // 已经销毁就别把服务留在那儿。
      if (ok) unawaited(_keeper.end());
      return;
    }
    _keeping = ok;
    _noticeBody = ok ? '准备中…' : '';
    if (!ok) {
      // 保活失败不拦执行：照样能跑，只是切后台/熄屏后可能被系统暂停。
      // 这件事必须写进日志，否则用户回来看到进度停住会以为是协议问题。
      _appendLog(TaskLog(
        '后台保活未启用：切到后台或熄屏后，系统可能暂停上报；保持本页在前台可正常执行',
        level: 'warn',
      ));
    } else if (!notifyOk) {
      // 保活起作用了，只是看不见。说清楚，免得用户到处找通知栏。
      _appendLog(TaskLog(
        '通知权限未授予：执行照常，但通知栏看不到进度，也无法从通知停止',
        level: 'warn',
      ));
    }
  }

  void _syncNotice() {
    if (!_keeping) return;
    final String body = _noticeText();
    if (body == _noticeBody) return;
    _noticeBody = body;
    // 不 await：通知只是展示，卡在通道上不该拖慢执行。
    unawaited(_keeper.update(
      title: '执行中：${chapterTitle.isEmpty ? '课程任务' : chapterTitle}',
      body: body,
    ));
  }

  String _noticeText() {
    final TaskProgress p = progress;
    if (p.phase == TaskPhase.preparing) return '准备中…';
    if (p.message == '正在停止…') return '正在停止…';
    final String passed = p.total > 0 ? '已通过 ${p.done} / ${p.total}' : '进行中';
    return p.current.isEmpty ? passed : '$passed · 正在 ${p.current}';
  }

  /// 执行结束：把通知改成最终结果再撤离前台，用户切回来之前也能看到结论。
  Future<void> _finishKeeping(TaskPhase phase) async {
    if (!_keeping) return;
    _keeping = false;
    _noticeBody = '';
    final TaskProgress p = progress;
    final String body = batchMode
        ? (p.message.isEmpty ? '已结束' : p.message)
        : (p.total > 0 ? '已通过 ${p.done} / ${p.total}' : p.message);
    await _keeper.finish(
      title: '${_phaseWord(phase)}：${chapterTitle.isEmpty ? '课程任务' : chapterTitle}',
      body: body,
    );
  }

  Future<void> _endKeeping() async {
    if (!_keeping) return;
    _keeping = false;
    _noticeBody = '';
    await _keeper.end();
  }

  static String _phaseWord(TaskPhase phase) => switch (phase) {
        TaskPhase.succeeded => '本次执行完成',
        TaskPhase.failed => '部分未通过',
        TaskPhase.needsAttention => '需要人工',
        TaskPhase.stopped => '已停止',
        TaskPhase.running => '执行中',
        TaskPhase.preparing => '准备中',
        TaskPhase.idle => '未开始',
      };

  /// 仅供测试与视觉取证：注入一次运行快照，不发起任何请求。
  void seedForPreview({
    required String courseName,
    required String chapterTitle,
    required TaskProgress progress,
    List<TaskLog> logs = const <TaskLog>[],
    Course? course,
    Chapter? chapter,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    _session++;
    _runner = null;
    _lastCourse = course;
    _lastChapters = chapter == null ? const <Chapter>[] : <Chapter>[chapter];
    this.courseName = courseName;
    this.chapterTitle = chapterTitle;
    this.progress = progress;
    this.logs
      ..clear()
      ..addAll(logs);
    droppedLogs = 0;
    this.startedAt = startedAt ?? DateTime.now();
    this.finishedAt = finishedAt;
    _onChanged();
  }
}

/// 批次内的章节分类：成功 / 无视频 / 有未通过任务点。
class _BatchTally {
  int ok = 0;
  int empty = 0;
  int failed = 0;
}

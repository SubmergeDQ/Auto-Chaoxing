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
  Chapter? _lastChapter;

  /// 保活是否真的起来了。只在 true 时刷通知，避免对没起的服务空喊。
  bool _keeping = false;

  /// 上一次推给通知的正文，用来去重：进度没变就不必刷。
  String _noticeBody = '';

  /// 会话令牌：reset 后旧 Runner 的回调仍可能到达，用令牌把它们丢掉。
  int _session = 0;
  bool _disposed = false;

  TaskPhase get phase => progress.phase;

  /// 正在读取或执行：此时不允许再起第二个任务（单账号串行）。
  bool get busy => phase == TaskPhase.preparing || phase == TaskPhase.running;

  bool get hasRun => startedAt != null;

  bool get canRerun => !busy && _lastCourse != null && _lastChapter != null;

  /// 当前是否处在「熄屏也继续跑」的状态，供界面如实说明。
  bool get keeping => _keeping;

  Future<void> start({required Course course, required Chapter chapter}) async {
    if (busy || _disposed) return;

    _lastCourse = course;
    _lastChapter = chapter;
    courseName = course.name;
    chapterTitle = chapter.title;
    logs.clear();
    droppedLogs = 0;
    startedAt = DateTime.now();
    finishedAt = null;
    progress = const TaskProgress(phase: TaskPhase.preparing, message: '准备中…');
    _onChanged();

    // 先起保活再发第一个请求：首个请求之后就要等 60 秒，晚起就白等一段。
    await _beginKeeping();
    if (_disposed) return;

    final int session = ++_session;
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
    finishedAt = DateTime.now();
    progress = progress.copyWith(phase: result.phase, message: result.message);
    _onChanged();
    await _finishKeeping(result);
  }

  /// 用上一次的课程与章节再跑一遍；已经通过的任务点平台会直接判过。
  Future<void> rerun() async {
    final Course? course = _lastCourse;
    final Chapter? chapter = _lastChapter;
    if (course == null || chapter == null || busy) return;
    await start(course: course, chapter: chapter);
  }

  void stop() {
    final TaskRunner? runner = _runner;
    if (runner == null) return;
    runner.requestStop();
    progress = progress.copyWith(message: '正在停止…');
    _syncNotice();
    _onChanged();
  }

  void clearLogs() {
    if (logs.isEmpty) return;
    logs.clear();
    droppedLogs = 0;
    _onChanged();
  }

  /// 断开账号或切换身份时清空会话，避免旧的执行状态挂到新账号上。
  void reset() {
    _session++;
    _runner?.requestStop();
    _runner = null;
    _lastCourse = null;
    _lastChapter = null;
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
  Future<void> _finishKeeping(VideoRunnerResult result) async {
    if (!_keeping) return;
    _keeping = false;
    _noticeBody = '';
    final TaskProgress p = progress;
    final String body = p.total > 0 ? '已通过 ${p.done} / ${p.total}' : result.message;
    await _keeper.finish(
      title: '${_phaseWord(result.phase)}：${chapterTitle.isEmpty ? '课程任务' : chapterTitle}',
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
    _lastChapter = chapter;
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

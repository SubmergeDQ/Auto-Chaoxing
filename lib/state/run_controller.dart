// 执行会话：持有 TaskRunner、进度与实时日志，把变化汇报给 AppState。
// 只做会话状态，不参与界面；界面通过 AppState 的 Listenable 刷新。
import '../core/chaoxing_api.dart';
import '../core/models.dart';
import '../core/task_runner.dart';

class RunController {
  RunController({
    required ChaoxingApi api,
    required void Function() onChanged,
    Future<void> Function(Duration)? sleep,
  })  : _api = api,
        _onChanged = onChanged,
        _sleep = sleep;

  /// 日志上限：长时间运行时只保留最近这些条，避免内存与渲染越跑越重。
  static const int maxLogs = 400;

  final ChaoxingApi _api;
  final void Function() _onChanged;
  final Future<void> Function(Duration)? _sleep;

  final List<TaskLog> logs = <TaskLog>[];

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

  /// 会话令牌：reset 后旧 Runner 的回调仍可能到达，用令牌把它们丢掉。
  int _session = 0;
  bool _disposed = false;

  TaskPhase get phase => progress.phase;

  /// 正在读取或执行：此时不允许再起第二个任务（单账号串行）。
  bool get busy => phase == TaskPhase.preparing || phase == TaskPhase.running;

  bool get hasRun => startedAt != null;

  bool get canRerun => !busy && _lastCourse != null && _lastChapter != null;

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

    final int session = ++_session;
    final TaskRunner runner = TaskRunner(
      _api,
      sleep: _sleep,
      onProgress: (TaskProgress p) {
        if (session != _session || _disposed) return;
        progress = p;
        _onChanged();
      },
      onLog: (TaskLog log) {
        if (session != _session || _disposed) return;
        logs.add(log);
        if (logs.length > maxLogs) {
          final int cut = logs.length - maxLogs;
          logs.removeRange(0, cut);
          droppedLogs += cut;
        }
        _onChanged();
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
    _onChanged();
  }

  void dispose() {
    _disposed = true;
    _session++;
    _runner?.requestStop();
  }

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

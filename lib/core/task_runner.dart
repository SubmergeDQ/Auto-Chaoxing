// 任务编排：串行队列、节流、断点、失败归类。
// 本文件不拼 URL、不解析 HTML，只调用 ChaoxingApi 并推进状态机。
import 'dart:async';

import 'chaoxing_api.dart';
import 'models.dart';

enum TaskPhase { idle, preparing, running, succeeded, failed, needsAttention, stopped }

class TaskLog {
  TaskLog(this.message, {this.level = 'info', DateTime? at}) : at = at ?? DateTime.now();

  final String message;
  final String level; // trace / info / warn / error
  final DateTime at;

  @override
  String toString() => '[$level] $message';
}

class TaskProgress {
  const TaskProgress({
    required this.phase,
    this.current = '',
    this.done = 0,
    this.total = 0,
    this.message = '',
  });

  final TaskPhase phase;
  final String current;
  final int done;
  final int total;
  final String message;

  TaskProgress copyWith({
    TaskPhase? phase,
    String? current,
    int? done,
    int? total,
    String? message,
  }) =>
      TaskProgress(
        phase: phase ?? this.phase,
        current: current ?? this.current,
        done: done ?? this.done,
        total: total ?? this.total,
        message: message ?? this.message,
      );
}

class VideoRunnerResult {
  VideoRunnerResult({
    required this.phase,
    required this.completed,
    required this.failed,
    required this.message,
  });

  final TaskPhase phase;
  final List<String> completed;
  final List<String> failed;
  final String message;
}

class TaskRunner {
  TaskRunner(
    this.api, {
    this.onProgress,
    this.onLog,
    Future<void> Function(Duration)? sleep,
  }) : _delay = sleep ?? _defaultDelay;

  /// 默认用真实计时；测试注入零延时，避免用例等真实秒数。
  static Future<void> _defaultDelay(Duration d) => Future<void>.delayed(d);

  final ChaoxingApi api;
  final void Function(TaskProgress)? onProgress;
  final void Function(TaskLog)? onLog;
  final Future<void> Function(Duration) _delay;

  bool _stopRequested = false;
  TaskProgress _progress = const TaskProgress(phase: TaskPhase.idle);

  TaskProgress get progress => _progress;

  void requestStop() => _stopRequested = true;

  void _emit(TaskProgress p) {
    _progress = p;
    onProgress?.call(p);
  }

  void _log(String msg, {String level = 'info'}) => onLog?.call(TaskLog(msg, level: level));

  /// 把一章里的所有视频任务点刷完。
  ///
  /// 返回前一定会给出终态：succeeded / failed / needsAttention / stopped。
  Future<VideoRunnerResult> runChapterVideos({
    required Course course,
    required Chapter chapter,
  }) async {
    _stopRequested = false;
    final List<String> completed = <String>[];
    final List<String> failed = <String>[];

    _emit(const TaskProgress(phase: TaskPhase.preparing, message: '读取章节卡片…'));

    final Result<ChapterCards> cards = await api.fetchCards(
      courseId: course.courseId,
      classId: course.classId,
      chapterId: chapter.chapterId,
      cpi: course.cpi,
    );
    if (cards is Err<ChapterCards>) {
      // 章节未开放和登录失效都需要人来处理，不能当作普通失败继续往下跑。
      final bool manual = cards.code == 'locked' || cards.code == 'authExpired';
      final TaskPhase phase = manual ? TaskPhase.needsAttention : TaskPhase.failed;
      final String message = cards.code == 'authExpired'
          ? '登录已失效，请重新连接账号后再继续'
          : cards.message;
      _emit(TaskProgress(phase: phase, message: message));
      return VideoRunnerResult(
        phase: phase,
        completed: completed,
        failed: failed,
        message: message,
      );
    }

    final ChapterCards data = (cards as Ok<ChapterCards>).value;
    final List<TaskPoint> videos = data.points.where((TaskPoint p) => p.isVideo).toList();
    if (videos.isEmpty) {
      _emit(const TaskProgress(phase: TaskPhase.succeeded, message: '本章没有视频任务点'));
      return VideoRunnerResult(
        phase: TaskPhase.succeeded,
        completed: completed,
        failed: failed,
        message: '本章没有视频任务点',
      );
    }
    _log('开始处理「${chapter.title}」，共 ${videos.length} 个视频任务点');

    final String uid = data.userId.isNotEmpty
        ? data.userId
        : (api.profile?.uid ?? '');

    for (int i = 0; i < videos.length; i++) {
      if (_stopRequested) {
        _emit(const TaskProgress(phase: TaskPhase.stopped, message: '已停止'));
        return VideoRunnerResult(
          phase: TaskPhase.stopped,
          completed: completed,
          failed: failed,
          message: '已停止，可从断点继续',
        );
      }

      final TaskPoint point = videos[i];
      _log('开始：${point.name}');
      _emit(TaskProgress(
        phase: TaskPhase.running,
        current: point.name,
        done: i,
        total: videos.length,
      ));

      final Result<VideoStatus> status = await api.videoStatus(point.objectId, data.fid);
      if (status is Err<VideoStatus>) {
        _log('${point.name}：${status.message}', level: 'error');
        failed.add(point.name);
        continue;
      }
      final VideoStatus vs = (status as Ok<VideoStatus>).value;

      final Result<bool> r = await _watchOne(
        report: data.reportUrl,
        dtoken: vs.dtoken,
        point: point,
        classId: course.classId,
        uid: uid,
        duration: vs.duration,
      );

      switch (r) {
        case Ok<bool>(value: true):
          completed.add(point.name);
          _log('完成：${point.name}', level: 'info');
        case Ok<bool>():
          failed.add(point.name);
          _log('未通过：${point.name}（可能有人脸抽检或倍速限制）', level: 'warn');
        case Err<bool>():
          // 用户主动停止不是失败，不要把任务点计进未通过。
          if (r.code == 'stopped') {
            _log('已停止：${point.name}（下次可从当前进度继续）', level: 'warn');
            _emit(TaskProgress(
              phase: TaskPhase.stopped,
              done: i,
              total: videos.length,
              message: '已停止',
            ));
            return VideoRunnerResult(
              phase: TaskPhase.stopped,
              completed: completed,
              failed: failed,
              message: '已停止，可从断点继续',
            );
          }
          // 人脸抽检、验证码、登录失效都不能重试，立即停下交回用户。
          if (r.code == 'needsAttention' || r.code == 'authExpired') {
            final String message = r.code == 'authExpired'
                ? '登录已失效，请重新连接账号后再继续'
                : r.message;
            _log(message, level: 'error');
            _emit(TaskProgress(
              phase: TaskPhase.needsAttention,
              done: i,
              total: videos.length,
              message: message,
            ));
            return VideoRunnerResult(
              phase: TaskPhase.needsAttention,
              completed: completed,
              failed: failed,
              message: message,
            );
          }
          failed.add(point.name);
          _log('失败：${point.name} -> ${r.message}', level: 'error');
      }

      // 任务点之间留间隔，单账号严格串行
      await _delay(const Duration(seconds: 2));
    }

    final bool allOk = failed.isEmpty;
    _log(
      '结束：完成 ${completed.length} / ${videos.length}'
      '${failed.isEmpty ? '' : '，${failed.length} 个未通过'}',
      level: allOk ? 'info' : 'warn',
    );
    _emit(TaskProgress(
      phase: allOk ? TaskPhase.succeeded : TaskPhase.failed,
      done: videos.length,
      total: videos.length,
      message: '完成 ${completed.length} / ${videos.length}',
    ));
    return VideoRunnerResult(
      phase: allOk ? TaskPhase.succeeded : TaskPhase.failed,
      completed: completed,
      failed: failed,
      message: '完成 ${completed.length} / ${videos.length}',
    );
  }

  Future<Result<bool>> _watchOne({
    required String report,
    required String dtoken,
    required TaskPoint point,
    required String classId,
    required String uid,
    required int duration,
  }) async {
    int playTime = 0;
    int errors = 0;
    const int step = 60; // 秒

    while (true) {
      if (_stopRequested) return const Err<bool>('stopped', '已停止');
      final bool last = playTime >= duration;
      final Result<bool> r = await api.reportProgress(
        reportUrl: report,
        dtoken: dtoken,
        point: point,
        classId: classId,
        uid: uid,
        playTime: last ? duration : playTime,
        duration: duration,
      );

      switch (r) {
        case Ok<bool>(value: true):
          return r;
        case Ok<bool>():
          errors = 0;
          _log(
            '${point.name}：已上报 ${last ? duration : playTime}s / ${duration}s',
            level: 'trace',
          );
        case Err<bool>():
          if (r.code == 'authExpired') return r;
          errors++;
          if (errors >= 3) return Err<bool>(r.code, '连续 3 次上报失败：${r.message}');
          await _delay(const Duration(seconds: 3));
          continue;
      }

      if (last) return r; // 已到结尾仍未通过
      playTime += step;
      await _delay(const Duration(seconds: 1));
    }
  }
}

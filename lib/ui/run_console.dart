// 任务执行页：状态卡 + 实时日志控制台，以及章节里的「执行本章视频」入口。
// 执行逻辑在 state/run_controller.dart，本文件只负责把状态讲清楚、把停止交到用户手上。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/log_export.dart';
import '../core/models.dart';
import '../core/task_runner.dart';
import '../state/app_state.dart';
import '../state/run_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// 开始执行前的确认：说明处理范围与「遇到人工验证会停下」，避免误触。
Future<void> startChapterRun(
  BuildContext context,
  AppState state,
  Chapter chapter, {
  VoidCallback? onOpenRun,
}) async {
  final Course? course = state.selectedCourse;
  if (course == null || state.run.busy) return;

  final int videoCount = (state.pointsFor(chapter.chapterId) ?? const <TaskPoint>[])
      .where((TaskPoint p) => p.isVideo)
      .length;
  // 一行一件事：范围 / 会怎么跑 / 什么时候停。挤成一段会把对话框撑到满屏。
  final String scope = videoCount > 0
      ? '将处理「${chapter.title}」中的 $videoCount 个视频任务点。'
      : '将处理「${chapter.title}」中的视频任务点。';

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: AcxColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AcxRadius.lg)),
      title: const Text(
        '开始执行本章视频',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AcxColors.textPrimary),
      ),
      // 定宽：不写宽度时 AlertDialog 会跟着最长那一行走，桌面端会拉成一条。
      content: SizedBox(
        width: 372,
        child: Text(
          // 断行位置是写死的：中文在这里按字换行，"作业" 和 "处理。" 被拆开很难看。
          '$scope\n文档与作业不在本次范围。\n\n'
          '执行时平台已通过的会跳过，已看过的从中间继续。\n'
          '耗时与视频总长相近，期间可以随时停止。\n\n'
          '遇到人脸抽检、验证码或登录失效会立即停止，\n交回你自己处理。',
          style: const TextStyle(fontSize: 13, height: 1.7, color: AcxColors.textSecondary),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(AcxSpacing.xl, 0, AcxSpacing.xl, AcxSpacing.xl),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('开始执行'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  // Android 13+ 没有通知权限时，前端服务照跑但通知不可见——
  // 用户既看不到进度，也点不到通知上的「停止」。所以先要一次，拒绝也照常执行。
  await state.runKeeper.ensureNotificationPermission();
  if (!context.mounted) return;

  unawaited(state.run.start(course: course, chapter: chapter));
  onOpenRun?.call();
}

class RunPage extends StatelessWidget {
  const RunPage({super.key, required this.state, this.onGoToCourses});

  final AppState state;
  final VoidCallback? onGoToCourses;

  @override
  Widget build(BuildContext context) {
    final RunController run = state.run;
    if (!run.hasRun && run.logs.isEmpty) {
      return AcxEmptyState(
        icon: Icons.bolt_outlined,
        title: '还没有开始执行',
        message: '到课程工作台展开章节，点「执行本章视频」。\n'
            '执行时这里会显示进度与日志；遇到人脸抽检、验证码或登录失效会立即停下。',
        action: onGoToCourses == null
            ? null
            : OutlinedButton.icon(
                onPressed: onGoToCourses,
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('去课程工作台'),
              ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _StatusCard(state: state),
          const SizedBox(height: AcxSpacing.lg),
          Expanded(child: _LogPanel(state: state)),
        ],
      ),
    );
  }
}

class _PhaseStyle {
  const _PhaseStyle(this.label, this.status, this.hint);

  final String label;
  final AcxStatus status;
  final String hint;
}

_PhaseStyle _phaseStyle(TaskPhase phase) {
  switch (phase) {
    case TaskPhase.idle:
      return const _PhaseStyle(
        '空闲',
        AcxStatus.idle,
        '选择章节并开始执行后，这里会显示实时进度与日志。',
      );
    case TaskPhase.preparing:
      return const _PhaseStyle(
        '准备中',
        AcxStatus.running,
        '正在读取章节任务点，读取完成后开始逐条上报进度。',
      );
    case TaskPhase.running:
      return const _PhaseStyle(
        '运行中',
        AcxStatus.running,
        '按 60 秒步长上报进度。可以随时停止，已通过的进度不会退回。',
      );
    case TaskPhase.succeeded:
      return const _PhaseStyle(
        '本次执行完成',
        AcxStatus.success,
        '可以回课程工作台核对任务点状态；平台若有延迟，稍后再看。',
      );
    case TaskPhase.failed:
      return const _PhaseStyle(
        '部分未通过',
        AcxStatus.failed,
        '可以再次执行重试；仍未通过时，多半是平台判定观看时长不足。',
      );
    case TaskPhase.needsAttention:
      return const _PhaseStyle(
        '需要人工',
        AcxStatus.attention,
        '已停止，不会自动重试。处理完上面的原因后再执行。',
      );
    case TaskPhase.stopped:
      return const _PhaseStyle(
        '已停止',
        AcxStatus.idle,
        '已停止。再次执行会从本章开头重新上报，平台会保留已通过的进度。',
      );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final RunController run = state.run;
    final _PhaseStyle style = _phaseStyle(run.phase);
    final bool hasChapter = run.chapterTitle.isNotEmpty;
    final bool showProgress = run.progress.total > 0 || run.busy;
    // 终止态必须把原因摆在卡片上：日志可能已经滚走，颜色 + 徽章不足以说明为什么停。
    final bool showReason =
        (run.phase == TaskPhase.failed || run.phase == TaskPhase.needsAttention) &&
            run.progress.message.isNotEmpty;

    return AcxSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      hasChapter ? run.chapterTitle : '还没有选择章节',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AcxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(run),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AcxSpacing.md),
              AcxStatusBadge(label: style.label, status: style.status),
            ],
          ),
          if (showProgress) ...<Widget>[
            const SizedBox(height: AcxSpacing.lg),
            _ProgressRow(run: run),
          ],
          if (showReason) ...<Widget>[
            const SizedBox(height: AcxSpacing.md),
            _ReasonBanner(
              message: run.progress.message,
              attention: run.phase == TaskPhase.needsAttention,
            ),
          ],
          const SizedBox(height: AcxSpacing.md),
          Text(
            style.hint,
            style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.textSecondary),
          ),
          const SizedBox(height: AcxSpacing.lg),
          Wrap(
            spacing: AcxSpacing.md,
            runSpacing: AcxSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (run.busy)
                OutlinedButton.icon(
                  // 停止是用户主动中断，不是失败，用中性描边而不是失败红。
                  onPressed: run.stop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('停止执行'),
                  style: OutlinedButton.styleFrom(foregroundColor: AcxColors.textPrimary),
                )
              else if (run.canRerun)
                FilledButton.icon(
                  onPressed: () => unawaited(run.rerun()),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('再次执行'),
                ),
              // 执行中不提供清空：日志是本次执行唯一的现场证据。
              // 顺序是「再次执行 → 复制日志 → 清空日志」：破坏性动作永远排最后。
              if (!run.busy && run.logs.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _copyLogs(context, run),
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                  label: const Text('复制日志'),
                  style: TextButton.styleFrom(foregroundColor: AcxColors.textSecondary),
                ),
              if (!run.busy && run.logs.isNotEmpty)
                TextButton.icon(
                  onPressed: run.clearLogs,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空日志'),
                  style: TextButton.styleFrom(foregroundColor: AcxColors.textSecondary),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyLogs(BuildContext context, RunController run) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String text = formatRunLog(
      courseName: run.courseName,
      chapterTitle: run.chapterTitle,
      phase: run.phase,
      summary: run.progress.message,
      logs: run.logs,
      startedAt: run.startedAt,
      finishedAt: run.finishedAt,
      dropped: run.droppedLogs,
    );
    // 不等剪贴板：这条通道在部分环境不回消息，await 会让反馈永远不出现。
    // 失败时另给一条提示，避免「说复制成功、其实没复制上」。
    Clipboard.setData(ClipboardData(text: text)).catchError((Object _) {
      messenger.showSnackBar(const SnackBar(content: Text('复制失败：剪贴板不可用')));
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('日志已复制，手机号与令牌已隐去')),
    );
  }

  String _subtitle(RunController run) {
    if (run.chapterTitle.isEmpty) {
      return '在课程工作台展开章节后点「执行本章视频」，这里会接着显示进度。';
    }
    final StringBuffer buffer = StringBuffer(run.courseName);
    final DateTime? started = run.startedAt;
    if (started != null) {
      final String start = _clock(started);
      final DateTime? finished = run.finishedAt;
      buffer.write(finished == null ? ' · $start 开始' : ' · $start – ${_clock(finished)}');
    }
    return buffer.toString();
  }
}

class _ReasonBanner extends StatelessWidget {
  const _ReasonBanner({required this.message, required this.attention});

  final String message;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final Color color = attention ? AcxColors.warning : AcxColors.danger;
    return Container(
      padding: const EdgeInsets.all(AcxSpacing.md),
      decoration: BoxDecoration(
        color: attention ? AcxColors.warningSoft : AcxColors.dangerSoft,
        borderRadius: BorderRadius.circular(AcxRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            attention ? Icons.front_hand_outlined : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AcxSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.run});

  final RunController run;

  @override
  Widget build(BuildContext context) {
    final int total = run.progress.total;
    final int done = run.progress.done;
    final bool known = total > 0;
    final String current = run.progress.current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: known ? (done / total).clamp(0.0, 1.0) : null,
            minHeight: 6,
            backgroundColor: AcxColors.surfaceMuted,
            valueColor: const AlwaysStoppedAnimation<Color>(AcxColors.brand),
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: known ? '已通过 $done / $total' : '正在读取任务点'),
              if (current.isNotEmpty)
                TextSpan(
                  text: ' · 正在上报 $current',
                  style: const TextStyle(color: AcxColors.textSecondary),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: AcxColors.textTertiary,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _LogPanel extends StatefulWidget {
  const _LogPanel({required this.state});

  final AppState state;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<TaskLog> logs = widget.state.run.logs;
    if (logs.length != _lastCount) {
      _lastCount = logs.length;
      // 新日志到达后跟到底部：控制台默认看最新一条。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '执行日志',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AcxColors.textSecondary,
              ),
            ),
            const Spacer(),
            if (logs.length >= RunController.maxLogs)
              const Text(
                '仅保留最近 400 条',
                style: TextStyle(fontSize: 11, color: AcxColors.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: AcxSpacing.md),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AcxColors.surface,
              borderRadius: BorderRadius.circular(AcxRadius.md),
              border: Border.all(color: AcxColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      '这次执行没有产生日志',
                      style: TextStyle(fontSize: 12, color: AcxColors.textTertiary),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: AcxSpacing.sm),
                    itemCount: logs.length,
                    itemBuilder: (BuildContext _, int index) => _LogLine(log: logs[index]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.log});

  final TaskLog log;

  @override
  Widget build(BuildContext context) {
    final bool warn = log.level == 'warn';
    final bool error = log.level == 'error';
    final bool trace = log.level == 'trace';
    // 日志是长段阅读，正文字号配足够的对比度：info 用主文字色，trace 低一档但不过浅。
    final Color color = error
        ? AcxColors.danger
        : warn
            ? AcxColors.warning
            : trace
                ? AcxColors.textSecondary
                : AcxColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.md, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _clockWithSeconds(log.at),
            style: const TextStyle(
              fontSize: 11,
              color: AcxColors.textTertiary,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AcxSpacing.sm),
          if (error || warn) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: error ? AcxColors.dangerSoft : AcxColors.warningSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                error ? '错误' : '警告',
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
            const SizedBox(width: AcxSpacing.sm),
          ],
          Expanded(
            child: Text(
              log.message,
              style: TextStyle(fontSize: 12, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _clockWithSeconds(DateTime t) => '${_clock(t)}:${_two(t.second)}';

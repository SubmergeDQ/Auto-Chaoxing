// 章节详情：宽屏作为右侧伴随面板，窄屏作为下钻页面。
// 任务点按展开懒加载，只读展示，不显示未经平台确认的「已完成」状态。
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import 'run_console.dart';
import 'theme.dart';
import 'widgets.dart';

class ChapterPane extends StatelessWidget {
  const ChapterPane({super.key, required this.state, this.onOpenRun});

  final AppState state;
  final VoidCallback? onOpenRun;

  @override
  Widget build(BuildContext context) {
    final Course? course = state.selectedCourse;
    if (course == null) {
      // 课程还没就绪时右栏保持安静，不给「从左侧选择一门课程」这种当前做不到的指引。
      final String? quiet = !state.signedIn
          ? '连接账号后，这里会显示课程的章节与任务点。'
          : state.coursesState == LoadState.loading
              ? '课程列表读取中，完成后这里会显示章节与任务点。'
              : state.coursesState == LoadState.error
                  ? '课程列表还没准备好，重试成功后这里会显示章节与任务点。'
                  : null;
      if (quiet != null) return _quietHint(quiet);
      return const AcxEmptyState(
        icon: Icons.account_tree_outlined,
        title: '从左侧选择一门课程',
        message: '选中课程后，这里会列出章节与任务点，方便和课程列表对照查看。',
      );
    }
    return _ChapterContent(state: state, course: course, onOpenRun: onOpenRun);
  }
}

/// 安静的单行提示：用于还没到「可以选择课程」这一步的状态，不抢主区的主角。
Widget _quietHint(String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(AcxSpacing.xxl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AcxColors.textTertiary),
      ),
    ),
  );
}

class ChapterDetailPage extends StatelessWidget {
  const ChapterDetailPage({super.key, required this.state, this.onOpenRun});

  final AppState state;
  final VoidCallback? onOpenRun;

  @override
  Widget build(BuildContext context) {
    final Course? course = state.selectedCourse;
    return Scaffold(
      appBar: AppBar(title: Text(course?.name ?? '章节')),
      body: course == null
          ? const AcxEmptyState(
              icon: Icons.account_tree_outlined,
              title: '课程信息已失效',
              message: '返回课程列表重新选择一门课程。',
            )
          : _ChapterContent(state: state, course: course, onOpenRun: onOpenRun),
    );
  }
}

class _ChapterContent extends StatelessWidget {
  const _ChapterContent({required this.state, required this.course, this.onOpenRun});

  final AppState state;
  final Course course;
  final VoidCallback? onOpenRun;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AcxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${course.teacher.isEmpty ? "未填写教师" : course.teacher}  ·  ${course.courseId} : ${course.classId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AcxSpacing.lg),
              // 章节可执行后这里不能再写「只读视图」：执行会向平台上报进度，
              // 只读指的是任务点数据不可手改，进度仍由平台判定。
              const AcxStatusBadge(label: '进度由平台判定', status: AcxStatus.idle),
            ],
          ),
          const SizedBox(height: AcxSpacing.md),
          Text(
            state.chaptersState == LoadState.ready
                ? '共 ${state.chapters.length} 章 · 展开章节时按需读取任务点'
                : '章节尚未读取完成 · 完成后可展开查看任务点',
            style: const TextStyle(fontSize: 12, color: AcxColors.textTertiary),
          ),
          const SizedBox(height: AcxSpacing.lg),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    switch (state.chaptersState) {
      case LoadState.idle:
      case LoadState.loading:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AcxStatusBadge(label: '读取中', status: AcxStatus.running),
              SizedBox(height: AcxSpacing.xl),
              SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
              SizedBox(height: AcxSpacing.lg),
              Text('正在读取章节…', style: TextStyle(fontSize: 13, color: AcxColors.textSecondary)),
              SizedBox(height: AcxSpacing.xs),
              Text('完成后会自动列出章节', style: TextStyle(fontSize: 12, color: AcxColors.textTertiary)),
            ],
          ),
        );
      case LoadState.error:
        return AcxErrorState(
          title: '章节读取失败',
          message: state.chaptersError ?? '未知错误',
          onRetry: () => unawaited(state.selectCourse(course)),
        );
      case LoadState.ready:
        if (state.chapters.isEmpty) {
          return const AcxEmptyState(
            icon: Icons.inbox_outlined,
            title: '这门课还没有章节',
            message: '章节可能尚未开放，或课程页面结构发生了变化。',
          );
        }
        return _ChapterList(state: state, onOpenRun: onOpenRun);
    }
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.state, this.onOpenRun});

  final AppState state;
  final VoidCallback? onOpenRun;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: state.chapters.length,
      separatorBuilder: (BuildContext _, int __) => const SizedBox(height: AcxSpacing.sm),
      itemBuilder: (BuildContext context, int index) => _ChapterTile(
        key: PageStorageKey<String>(state.chapters[index].chapterId),
        state: state,
        chapter: state.chapters[index],
        index: index,
        onOpenRun: onOpenRun,
      ),
    );
  }
}

/// 自定义展开卡片：不用 ExpansionTile，避免 Material 3 给展开态叠一层灰底，
/// 让整组卡片保持同一表面；展开态改用序号底色与描边表达，而不是整块变色。
class _ChapterTile extends StatefulWidget {
  const _ChapterTile({
    super.key,
    required this.state,
    required this.chapter,
    required this.index,
    this.onOpenRun,
  });

  final AppState state;
  final Chapter chapter;
  final int index;
  final VoidCallback? onOpenRun;

  @override
  State<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends State<_ChapterTile> {
  bool _expanded = false;

  void _toggle() {
    final bool next = !_expanded;
    setState(() => _expanded = next);
    if (next) unawaited(widget.state.loadPoints(widget.chapter));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AcxColors.surface,
        borderRadius: BorderRadius.circular(AcxRadius.md),
        border: Border.all(color: _expanded ? AcxColors.brand : AcxColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AcxSpacing.lg,
                vertical: AcxSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _expanded ? AcxColors.brand : AcxColors.brandSoft,
                      borderRadius: BorderRadius.circular(AcxRadius.sm),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _expanded ? Colors.white : AcxColors.brand,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AcxSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AcxColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '章节 ${widget.chapter.chapterId}',
                          style: const TextStyle(fontSize: 11, color: AcxColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AcxSpacing.sm),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 20,
                    color: AcxColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AcxSpacing.lg, 0, AcxSpacing.lg, AcxSpacing.lg,
              ),
              child: _PointsView(
                state: widget.state,
                chapter: widget.chapter,
                onOpenRun: widget.onOpenRun,
              ),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: AcxDurations.fast,
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

class _PointsView extends StatelessWidget {
  const _PointsView({required this.state, required this.chapter, this.onOpenRun});

  final AppState state;
  final Chapter chapter;
  final VoidCallback? onOpenRun;

  @override
  Widget build(BuildContext context) {
    if (state.isChapterLoading(chapter.chapterId)) {
      return const Padding(
        padding: EdgeInsets.all(AcxSpacing.lg),
        child: Row(
          children: <Widget>[
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: AcxSpacing.md),
            Text('正在读取任务点…', style: TextStyle(fontSize: 12, color: AcxColors.textSecondary)),
          ],
        ),
      );
    }

    final String? error = state.errorFor(chapter.chapterId);
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(AcxSpacing.md),
        decoration: BoxDecoration(
          color: AcxColors.warningSoft,
          borderRadius: BorderRadius.circular(AcxRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.front_hand_outlined, size: 16, color: AcxColors.warning),
                SizedBox(width: AcxSpacing.sm),
                Text(
                  '需要人工处理',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AcxSpacing.sm),
            Text(
              error,
              style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.warning),
            ),
            const SizedBox(height: AcxSpacing.sm),
            const Text(
              '已停止，不会自动重试。完成前置条件后再展开本章。',
              style: TextStyle(fontSize: 12, height: 1.5, color: AcxColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final List<TaskPoint>? points = state.pointsFor(chapter.chapterId);
    if (points == null) {
      return const Padding(
        padding: EdgeInsets.all(AcxSpacing.md),
        child: Text('展开后读取任务点', style: TextStyle(fontSize: 12, color: AcxColors.textTertiary)),
      );
    }
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AcxSpacing.md),
        child: Text('本章没有任务点', style: TextStyle(fontSize: 12, color: AcxColors.textSecondary)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 1),
        const SizedBox(height: AcxSpacing.sm),
        ...points.map(
          (TaskPoint point) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Icon(_typeIcon(point.type), size: 16, color: AcxColors.textSecondary),
                const SizedBox(width: AcxSpacing.md),
                Expanded(
                  child: Text(
                    point.name.isEmpty ? '未命名任务点' : point.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AcxColors.textPrimary),
                  ),
                ),
                const SizedBox(width: AcxSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AcxColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _typeLabel(point.type),
                    style: const TextStyle(fontSize: 11, color: AcxColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
        _RunFooter(
          state: state,
          chapter: chapter,
          points: points,
          onOpenRun: onOpenRun,
        ),
      ],
    );
  }
}

/// 章节里的唯一主动作：执行本章视频。执行中、已归档、未连接时给出原因而不是假开关。
class _RunFooter extends StatelessWidget {
  const _RunFooter({
    required this.state,
    required this.chapter,
    required this.points,
    this.onOpenRun,
  });

  final AppState state;
  final Chapter chapter;
  final List<TaskPoint> points;
  final VoidCallback? onOpenRun;

  @override
  Widget build(BuildContext context) {
    final List<TaskPoint> videos = points.where((TaskPoint p) => p.isVideo).toList();
    if (videos.isEmpty) {
      if (points.isEmpty) return const SizedBox.shrink();
      // 有任务点但没有视频：不要静默留白，否则用户会以为客户端漏读了任务，
      // 或者反复点章节找那个「执行」按钮。
      final Map<String, int> byType = <String, int>{};
      for (final TaskPoint p in points) {
        final String label = _typeLabel(p.type);
        byType[label] = (byType[label] ?? 0) + 1;
      }
      final String detail =
          byType.entries.map((MapEntry<String, int> e) => '${e.value} 个${e.key}').join('、');
      return Padding(
        padding: const EdgeInsets.only(top: AcxSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Divider(height: 1),
            const SizedBox(height: AcxSpacing.md),
            Row(
              children: <Widget>[
                const Icon(Icons.info_outline_rounded, size: 16, color: AcxColors.textTertiary),
                const SizedBox(width: AcxSpacing.sm),
                Expanded(
                  child: Text(
                    '本章 $detail 任务点，都不在本客户端的自动执行范围内，需要在手机端完成。',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: AcxColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final bool archived = state.selectedCourse?.archived ?? false;
    final bool busy = state.run.busy;
    final bool canRun = !archived && !busy && state.signedIn;

    // 重跑一章时把「会跳过什么」提前说清：用户看到任务点没动，也有据可查。
    final int passedCount = videos.where((TaskPoint p) => p.passed == true).length;
    final int resumeCount = videos.where((TaskPoint p) => p.canResume).length;

    final String hint;
    if (archived) {
      hint = '已归档课程不能执行';
    } else if (!state.signedIn) {
      hint = '连接账号后才能执行';
    } else if (busy) {
      hint = '已有章节在执行，结束后可以再开始';
    } else {
      final List<String> notes = <String>[
        if (passedCount > 0) '$passedCount 个平台已通过将跳过',
        if (resumeCount > 0) '$resumeCount 个从中间继续',
        if (passedCount == 0 && resumeCount == 0) '耗时与视频总长相近',
      ];
      // 混排章节里视频只占一部分，剩下的文档/作业不会被执行；
      // 不写出来用户会以为点一次就把整章做完了。
      final int others = points.length - videos.length;
      hint = '${videos.length} 个视频任务点 · ${notes.join('，')}'
          '${others > 0 ? '；另有 $others 个非视频任务点需在手机端完成' : ''}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: AcxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Divider(height: 1),
          const SizedBox(height: AcxSpacing.md),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AcxSpacing.md,
            runSpacing: AcxSpacing.sm,
            children: <Widget>[
              Text(hint, style: const TextStyle(fontSize: 12, color: AcxColors.textTertiary)),
              FilledButton.icon(
                onPressed: canRun
                    ? () => unawaited(
                          startChapterRun(context, state, chapter, onOpenRun: onOpenRun),
                        )
                    : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(busy ? '任务执行中' : '执行本章视频'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'video':
      return '视频';
    case 'document':
      return '文档';
    case 'workid':
      return '作业';
    case 'read':
      return '阅读';
    case 'live':
      return '直播';
    default:
      return type.isEmpty ? '其他' : type;
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'video':
      return Icons.play_circle_outline_rounded;
    case 'document':
      return Icons.description_outlined;
    case 'workid':
      return Icons.assignment_outlined;
    case 'read':
      return Icons.chrome_reader_mode_outlined;
    case 'live':
      return Icons.live_tv_outlined;
    default:
      return Icons.circle_outlined;
  }
}

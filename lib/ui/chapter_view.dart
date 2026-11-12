// 章节详情：宽屏作为右侧伴随面板，窄屏作为下钻页面。
// 任务点按展开懒加载，只读展示，不显示未经平台确认的「已完成」状态。
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class ChapterPane extends StatelessWidget {
  const ChapterPane({super.key, required this.state});

  final AppState state;

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
    return _ChapterContent(state: state, course: course);
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
  const ChapterDetailPage({super.key, required this.state});

  final AppState state;

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
          : _ChapterContent(state: state, course: course),
    );
  }
}

class _ChapterContent extends StatelessWidget {
  const _ChapterContent({required this.state, required this.course});

  final AppState state;
  final Course course;

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
              // 「只读视图」是常驻模式标记，不随加载 / 失败状态改变，避免标签位语义跳动。
              const AcxStatusBadge(label: '只读视图', status: AcxStatus.idle),
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
        return _ChapterList(state: state);
    }
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.state});

  final AppState state;

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
  });

  final AppState state;
  final Chapter chapter;
  final int index;

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
              child: _PointsView(state: widget.state, chapter: widget.chapter),
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
  const _PointsView({required this.state, required this.chapter});

  final AppState state;
  final Chapter chapter;

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
      ],
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

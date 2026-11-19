// 作业页：只读列表 + 打开网页作答。
//
// 不在这里提交：作答页的隐藏字段（workAnswerId / temAnswer / totalQuestionNum …）
// 还没抓包确认，猜字段提交会出现「本地以为交了、平台没收到」。入口给到网页，
// 提交与校验都在平台页面上完成。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/homework_rules.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../state/homework_controller.dart';
import 'quiz_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeworkPage extends StatefulWidget {
  const HomeworkPage({super.key, required this.state, required this.course});

  final AppState state;
  final Course course;

  @override
  State<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends State<HomeworkPage> {
  HomeworkController get _homework => widget.state.homework;

  @override
  void initState() {
    super.initState();
    // 首帧后拉取：控制器会同步 notifyListeners，不能在 build 阶段触发。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_homework.open(widget.course));
    });
  }

  Future<void> _openHomework(HomeworkItem item) async {
    final Uri uri = Uri.parse(
      homeworkPageUrl(course: widget.course, workId: item.workId),
    );
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('打不开浏览器：请手动到学习通网页完成作业')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作业')),
      body: AnimatedBuilder(
        animation: widget.state,
        builder: (BuildContext context, Widget? _) => _content(),
      ),
    );
  }

  Widget _content() {
    if (_homework.loading && _homework.items.isEmpty) {
      return const Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    final String? error = _homework.error;
    if (error != null && _homework.items.isEmpty) {
      return AcxErrorState(
        title: '作业列表读取失败',
        message: error,
        onRetry: () => unawaited(_homework.refresh()),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AcxColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '「自动答题」会用万卷题库查答案并直接提交；'
                    '「打开作答页」仍在浏览器里手动完成',
                    style: TextStyle(fontSize: 12, color: AcxColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AcxSpacing.md),
            IconButton(
              onPressed: () => unawaited(showWanJuanTokenDialog(context, widget.state)),
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
              tooltip: '题库 Token',
            ),
            OutlinedButton.icon(
              onPressed: _homework.loading ? null : () => unawaited(_homework.refresh()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新'),
            ),
          ],
        ),
        const SizedBox(height: AcxSpacing.lg),
        if (_homework.items.isEmpty)
          AcxSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '这门课暂时没有作业',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AcxSpacing.sm),
                Text(
                  _homework.loading
                      ? '正在读取…'
                      : '老师发布作业后点「刷新」就能看到；列表只展示平台返回的内容。',
                  style: const TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
                ),
              ],
            ),
          )
        else
          ..._homework.items.map(
            (HomeworkItem item) => Padding(
              padding: const EdgeInsets.only(bottom: AcxSpacing.md),
              child: _HomeworkCard(
                item: item,
                onOpen: () => unawaited(_openHomework(item)),
                onAuto: () => unawaited(
                  startAutoQuiz(
                    context,
                    widget.state,
                    course: widget.course,
                    item: item,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: AcxSpacing.md),
        const Text(
          '自动答题会把题库匹配到的答案填入并直接提交，未匹配的题会留空；'
          '提交结果以平台回执和作业列表状态为准。'
          '题库是第三方收费服务，Token 与扣费由你自己在万卷题库管理。'
          '网页作答入口仍可在浏览器里手动完成。',
          style: TextStyle(fontSize: 12, height: 1.7, color: AcxColors.textTertiary),
        ),
      ],
    );
  }
}

class _HomeworkCard extends StatelessWidget {
  const _HomeworkCard({
    required this.item,
    required this.onOpen,
    required this.onAuto,
  });

  final HomeworkItem item;
  final VoidCallback onOpen;
  final VoidCallback onAuto;

  @override
  Widget build(BuildContext context) {
    final bool? done = item.completed;
    final String label = done == true
        ? '已交'
        : done == false
            ? '未交'
            : '状态未知';
    final AcxStatus status = done == true
        ? AcxStatus.success
        : done == false
            ? AcxStatus.attention
            : AcxStatus.idle;

    return AcxSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.assignment_outlined, size: 18, color: AcxColors.textSecondary),
              const SizedBox(width: AcxSpacing.sm),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AcxSpacing.sm),
              AcxStatusBadge(label: label, status: status),
            ],
          ),
          const SizedBox(height: AcxSpacing.sm),
          Text(
            item.endAt == null
                ? '截止时间未知'
                : '截止 ${_time(item.endAt!)}${item.expired ? ' · 已过截止' : ''}',
            style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
          ),
          const SizedBox(height: AcxSpacing.md),
          Wrap(
            spacing: AcxSpacing.sm,
            runSpacing: AcxSpacing.sm,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('打开作答页'),
              ),
              Tooltip(
                message: done == true
                    ? '这份作业已提交，不重复提交'
                    : item.expired
                        ? '已过截止时间，平台可能不再接收'
                        : '用万卷题库查答案并直接提交',
                child: FilledButton.icon(
                  onPressed: (done == true || item.expired) ? null : onAuto,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('自动答题'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

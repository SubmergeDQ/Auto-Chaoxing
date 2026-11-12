// 代表性页面：课程工作台。
// 宽屏为「课程列表 / 章节详情」主从双栏，窄屏退化为列表 + 下钻。
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import 'chapter_view.dart';
import 'theme.dart';
import 'widgets.dart';

class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 1100;
    final Widget list = _CourseListPane(state: state, wide: wide);
    if (!wide) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 360, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: ChapterPane(state: state)),
      ],
    );
  }
}

class _CourseListPane extends StatelessWidget {
  const _CourseListPane({required this.state, required this.wide});

  final AppState state;
  final bool wide;

  void _openCourse(BuildContext context, Course course) {
    unawaited(state.selectCourse(course));
    if (wide) return;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => ChapterDetailPage(state: state),
        ),
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext _) => _LoginDialog(state: state),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MetricsRow(state: state, open: wide),
          if (wide &&
              state.signedIn &&
              state.coursesState == LoadState.ready &&
              state.courses.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AcxSpacing.md),
              child: Text(
                '选中课程后，右侧显示章节与任务点',
                style: TextStyle(fontSize: 12, color: AcxColors.textTertiary),
              ),
            ),
          const SizedBox(height: AcxSpacing.lg),
          Expanded(child: _content(context)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (!state.signedIn) {
      return AcxEmptyState(
        icon: Icons.lock_outline_rounded,
        title: '先连接你的学习通账号',
        message: '连接后可读取课程、章节与任务点。\n请只用于你自己的账号和已选修课程。',
        action: FilledButton.icon(
          onPressed: () => _showLoginDialog(context),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('连接账号'),
        ),
      );
    }
    switch (state.coursesState) {
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
              Text('正在读取课程列表…', style: TextStyle(fontSize: 13, color: AcxColors.textSecondary)),
              SizedBox(height: AcxSpacing.xs),
              Text('完成后会自动显示课程', style: TextStyle(fontSize: 12, color: AcxColors.textTertiary)),
            ],
          ),
        );
      case LoadState.error:
        return AcxErrorState(
          title: '课程列表读取失败',
          message: state.coursesError ?? '未知错误',
          onRetry: () => unawaited(state.loadCourses()),
        );
      case LoadState.ready:
        if (state.courses.isEmpty) {
          return const AcxEmptyState(
            icon: Icons.inbox_outlined,
            title: '这个账号还没有课程',
            message: '如果刚选完课，等平台同步后再回来刷新。',
          );
        }
        return ListView.separated(
          itemCount: state.courses.length,
          separatorBuilder: (BuildContext _, int __) => const SizedBox(height: AcxSpacing.md),
          itemBuilder: (BuildContext context, int index) {
            final Course course = state.courses[index];
            return _CourseTile(
              course: course,
              selected: state.selectedCourse?.key == course.key,
              showChevron: !wide,
              onTap: () => _openCourse(context, course),
            );
          },
        );
    }
  }
}

/// 宽屏时指标直接排在开放画布上（只留一条分隔线），与下方卡片列表形成两种质感；
/// 窄屏仍用卡片盒收拢，避免小屏上信息发散。
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.state, required this.open});

  final AppState state;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      children: <Widget>[
        Expanded(child: AcxMetric(label: '在修课程', value: '${state.activeCourses}')),
        Expanded(
          child: AcxMetric(
            label: '已归档',
            value: '${state.archivedCourses}',
            accent: AcxColors.textSecondary,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('连接状态', style: TextStyle(fontSize: 12, color: AcxColors.textSecondary)),
              const SizedBox(height: 6),
              AcxStatusBadge(
                label: state.signedIn ? '已连接' : '未连接',
                status: state.signedIn ? AcxStatus.success : AcxStatus.idle,
              ),
            ],
          ),
        ),
      ],
    );

    if (!open) {
      return AcxSectionCard(
        padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.xl, vertical: AcxSpacing.lg),
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsets.only(bottom: AcxSpacing.lg),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AcxColors.border)),
      ),
      child: row,
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.selected,
    required this.showChevron,
    required this.onTap,
  });

  final Course course;
  final bool selected;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AcxColors.brandSoft : AcxColors.surface,
      borderRadius: BorderRadius.circular(AcxRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AcxRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AcxSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AcxRadius.md),
            border: Border.all(color: selected ? AcxColors.brand : AcxColors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? AcxColors.brand : AcxColors.brandSoft,
                  borderRadius: BorderRadius.circular(AcxRadius.sm),
                ),
                child: Icon(
                  Icons.class_outlined,
                  size: 19,
                  color: selected ? Colors.white : AcxColors.brand,
                ),
              ),
              const SizedBox(width: AcxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AcxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      course.teacher.isEmpty ? '未填写教师' : course.teacher,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${course.courseId} : ${course.classId}',
                      style: const TextStyle(fontSize: 11, color: AcxColors.textTertiary),
                    ),
                  ],
                ),
              ),
              if (course.archived)
                const Padding(
                  padding: EdgeInsets.only(right: AcxSpacing.sm),
                  child: AcxStatusBadge(label: '已归档', status: AcxStatus.idle),
                ),
              // 宽屏就地换右栏，不用下钻箭头；窄屏才会进新页面，才给箭头。
              if (selected && !showChevron)
                const Text(
                  '当前查看',
                  style: TextStyle(fontSize: 11, color: AcxColors.brand),
                )
              else if (showChevron)
                const Icon(Icons.chevron_right_rounded, size: 20, color: AcxColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.state});

  final AppState state;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? error = await widget.state.signIn(_username.text, _password.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AcxColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AcxRadius.lg)),
      titlePadding: const EdgeInsets.fromLTRB(AcxSpacing.xl, AcxSpacing.xl, AcxSpacing.xl, 0),
      contentPadding: const EdgeInsets.all(AcxSpacing.xl),
      title: const Text(
        '连接学习通账号',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AcxColors.textPrimary),
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '账号密码只在本机用于加密登录，不写入日志，也不会上传到任何服务。',
                style: TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
              ),
              const SizedBox(height: AcxSpacing.xl),
              TextFormField(
                controller: _username,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '手机号', hintText: '登录用的手机号'),
                validator: (String? v) =>
                    (v == null || v.trim().isEmpty) ? '请输入手机号' : null,
              ),
              const SizedBox(height: AcxSpacing.lg),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码', hintText: '学习通登录密码'),
                validator: (String? v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                onFieldSubmitted: (_) => unawaited(_submit()),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AcxSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AcxSpacing.md),
                  decoration: BoxDecoration(
                    color: AcxColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AcxRadius.sm),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(AcxSpacing.xl, 0, AcxSpacing.xl, AcxSpacing.xl),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('连接'),
        ),
      ],
    );
  }
}

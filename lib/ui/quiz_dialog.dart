// 自动刷题的两个入口：题库 Token 设置 + 执行进度面板。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/question_bank.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

const String _kBankHome = 'https://tk.wanjuantiku.com/';

/// 设置并校验万卷题库 Token。返回保存后的 Token；取消返回 null。
Future<String?> showWanJuanTokenDialog(BuildContext context, AppState state) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext _) => _TokenDialog(state: state),
  );
}

class _TokenDialog extends StatefulWidget {
  const _TokenDialog({required this.state});

  final AppState state;

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  late final TextEditingController _token =
      TextEditingController(text: widget.state.wanjuanToken);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _verifyAndSave() async {
    final String token = _token.text.trim();
    if (!WanJuanBank.isValidToken(token)) {
      setState(() => _error = 'Token 应为 32 位数字/小写字母');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<int> result = await WanJuanBank(token: token).checkLeft();
    if (!mounted) return;
    if (result is Err<int>) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    final int left = (result as Ok<int>).value;
    if (left < 0) {
      setState(() {
        _busy = false;
        _error = 'Token 无效或未注册，请到万卷题库确认';
      });
      return;
    }
    await widget.state.saveWanJuanToken(token);
    if (!mounted) return;
    Navigator.of(context).pop(token);
  }

  Future<void> _openBank() async {
    await launchUrl(Uri.parse(_kBankHome), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AcxColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AcxRadius.lg)),
      title: const Text(
        '万卷题库 Token',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AcxColors.textPrimary),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '自动刷题使用万卷题库。Token 只保存在本机，用它查询答案会按次扣费。'
              '没有 Token 时可以先打开题库网站获取。',
              style: TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
            ),
            const SizedBox(height: AcxSpacing.md),
            TextButton.icon(
              onPressed: () => unawaited(_openBank()),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('打开万卷题库（获取 / 充值）'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
                foregroundColor: AcxColors.brand,
              ),
            ),
            const SizedBox(height: AcxSpacing.md),
            TextField(
              controller: _token,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Token',
                hintText: '32 位数字 / 小写字母',
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AcxSpacing.md),
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
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_verifyAndSave()),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('校验并保存'),
        ),
      ],
    );
  }
}

/// 打开自动答题进度面板。没有 Token 时先让用户填。
Future<void> startAutoQuiz(
  BuildContext context,
  AppState state, {
  required Course course,
  required HomeworkItem item,
}) async {
  if (state.quiz.busy) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已有一份作业正在自动作答')),
    );
    return;
  }
  String token = state.wanjuanToken;
  if (token.isEmpty) {
    final String? saved = await showWanJuanTokenDialog(context, state);
    if (saved == null || saved.isEmpty || !context.mounted) return;
    token = saved;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext _) => _QuizSheet(
      state: state,
      course: course,
      item: item,
      token: token,
    ),
  );
  // 提交后刷新列表，让「已交」状态尽快反映平台结果。
  if (state.quiz.submitted) {
    await state.homework.refresh();
  }
}

class _QuizSheet extends StatefulWidget {
  const _QuizSheet({
    required this.state,
    required this.course,
    required this.item,
    required this.token,
  });

  final AppState state;
  final Course course;
  final HomeworkItem item;
  final String token;

  @override
  State<_QuizSheet> createState() => _QuizSheetState();
}

class _QuizSheetState extends State<_QuizSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        widget.state.quiz.run(
          course: widget.course,
          item: widget.item,
          token: widget.token,
          userId: widget.state.profile?.uid ?? '',
          courseName: widget.course.name,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (BuildContext context, Widget? _) {
        final quiz = widget.state.quiz;
        return PopScope(
          canPop: !quiz.busy,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            decoration: const BoxDecoration(
              color: AcxColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AcxRadius.lg)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AcxSpacing.xl,
                  AcxSpacing.lg,
                  AcxSpacing.xl,
                  AcxSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.auto_awesome_outlined, size: 20, color: AcxColors.brand),
                        const SizedBox(width: AcxSpacing.sm),
                        Expanded(
                          child: Text(
                            quiz.title ?? widget.item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AcxColors.textPrimary,
                            ),
                          ),
                        ),
                        if (quiz.left != null)
                          AcxStatusBadge(
                            label: '题库 ${quiz.left} 次',
                            status: AcxStatus.idle,
                          ),
                      ],
                    ),
                    const SizedBox(height: AcxSpacing.md),
                    LinearProgressIndicator(
                      value: quiz.total == 0 ? null : quiz.done / quiz.total,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor: AcxColors.border,
                      color: AcxColors.brand,
                    ),
                    const SizedBox(height: AcxSpacing.sm),
                    Text(
                      '进度 ${quiz.done}/${quiz.total} · 已匹配 ${quiz.answered} 题'
                      '${quiz.busy ? ' · 正在执行' : ''}',
                      style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
                    ),
                    const SizedBox(height: AcxSpacing.md),
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 120),
                        decoration: BoxDecoration(
                          color: AcxColors.idleSoft,
                          borderRadius: BorderRadius.circular(AcxRadius.md),
                          border: Border.all(color: AcxColors.border),
                        ),
                        child: quiz.logs.isEmpty
                            ? const Center(
                                child: Text(
                                  '正在准备…',
                                  style: TextStyle(fontSize: 12, color: AcxColors.textTertiary),
                                ),
                              )
                            : ListView.builder(
                                reverse: true,
                                padding: const EdgeInsets.all(AcxSpacing.md),
                                itemCount: quiz.logs.length,
                                itemBuilder: (BuildContext _, int i) {
                                  final String line = quiz.logs[quiz.logs.length - 1 - i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      line,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        fontFamily: 'Consolas',
                                        color: line.startsWith('×')
                                            ? AcxColors.danger
                                            : AcxColors.textSecondary,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    if (quiz.error != null) ...<Widget>[
                      const SizedBox(height: AcxSpacing.md),
                      _Banner(
                        color: AcxColors.dangerSoft,
                        textColor: AcxColors.danger,
                        text: quiz.error!,
                      ),
                    ],
                    if (quiz.resultMessage != null) ...<Widget>[
                      const SizedBox(height: AcxSpacing.md),
                      _Banner(
                        color: quiz.submitOk == false ? AcxColors.warningSoft : AcxColors.brandSoft,
                        textColor: quiz.submitOk == false ? AcxColors.warning : AcxColors.brand,
                        text: quiz.resultMessage!,
                      ),
                    ],
                    const SizedBox(height: AcxSpacing.md),
                    Row(
                      children: <Widget>[
                        if (quiz.busy)
                          OutlinedButton(
                            onPressed: quiz.canCancel ? () => quiz.cancel() : null,
                            child: Text(quiz.cancelled ? '正在停止…' : '停止'),
                          ),
                        const Spacer(),
                        FilledButton(
                          onPressed: quiz.busy ? null : () => Navigator.of(context).pop(),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.textColor,
    required this.text,
  });

  final Color color;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AcxSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AcxRadius.sm),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.5, color: textColor),
      ),
    );
  }
}

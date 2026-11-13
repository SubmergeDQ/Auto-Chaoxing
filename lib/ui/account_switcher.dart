// 账号切换对话框：列出本机保存过的账号，点击切换、可移除、可添加新账号。
//
// 多账号的「切换」不是重登：每个账号的 cookie 在独立目录里，
// 切过去只校验一次会话，成功就恢复课程列表。
import 'package:flutter/material.dart';

import '../platform/session_store.dart';
import '../state/app_state.dart';
import 'courses_page.dart' show showLoginDialog;
import 'theme.dart';
import 'widgets.dart';

Future<void> showAccountSwitcher(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => _AccountSwitcherDialog(state: state),
  );
}

class _AccountSwitcherDialog extends StatefulWidget {
  const _AccountSwitcherDialog({required this.state});

  final AppState state;

  @override
  State<_AccountSwitcherDialog> createState() => _AccountSwitcherDialogState();
}

class _AccountSwitcherDialogState extends State<_AccountSwitcherDialog> {
  bool _busy = false;
  String? _error;

  AppState get _state => widget.state;

  Future<void> _switch(String uid, String name) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? error = await _state.switchAccount(uid);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 $name')),
      );
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _remove(StoredAccount account) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _state.removeAccount(account.uid);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _addAccount() async {
    // 直接叠一层登录框：登录成功后账号列表会通过 AnimatedBuilder 自动刷新，
    // 不需要先关掉这个对话框再重开。
    await showLoginDialog(context, _state);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AcxColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AcxRadius.lg)),
      title: const Text(
        '账号',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AcxColors.textPrimary),
      ),
      content: SizedBox(
        width: 420,
        child: AnimatedBuilder(
          animation: _state,
          builder: (BuildContext context, Widget? _) {
            final List<StoredAccount> accounts = _state.accounts;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AcxSpacing.lg),
                    child: Text(
                      '本机还没有保存过账号。登录后会自动记住，下次可以直接切换。',
                      style: TextStyle(fontSize: 13, height: 1.6, color: AcxColors.textSecondary),
                    ),
                  )
                else
                  ...accounts.map(
                    (StoredAccount a) => Padding(
                      padding: const EdgeInsets.only(bottom: AcxSpacing.sm),
                      child: _AccountRow(
                        account: a,
                        current: a.uid == _state.activeUid && _state.signedIn,
                        busy: _busy,
                        onSwitch: () => _switch(a.uid, a.name),
                        onRemove: () => _remove(a),
                      ),
                    ),
                  ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: AcxSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AcxSpacing.md),
                    decoration: BoxDecoration(
                      color: AcxColors.warningSoft,
                      borderRadius: BorderRadius.circular(AcxRadius.sm),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.warning),
                    ),
                  ),
                ],
                const SizedBox(height: AcxSpacing.md),
                const Text(
                  '切换账号只校验本地会话，不会重新登录；会话过期时再输入密码即可。'
                  '移除账号会删掉该账号的 cookie 文件。',
                  style: TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textTertiary),
                ),
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _addAccount(),
          child: const Text('添加账号'),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.current,
    required this.busy,
    required this.onSwitch,
    required this.onRemove,
  });

  final StoredAccount account;
  final bool current;
  final bool busy;
  final VoidCallback onSwitch;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final String detail = <String>[
      if (account.school.trim().isNotEmpty) account.school.trim(),
      'uid ${account.uid}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.md, vertical: AcxSpacing.sm),
      decoration: BoxDecoration(
        color: current ? AcxColors.brandSoft : AcxColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AcxRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            current ? Icons.account_circle_rounded : Icons.account_circle_outlined,
            size: 22,
            color: current ? AcxColors.brand : AcxColors.textSecondary,
          ),
          const SizedBox(width: AcxSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        account.name.isEmpty ? '未命名账号' : account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AcxColors.textPrimary,
                        ),
                      ),
                    ),
                    if (current) ...<Widget>[
                      const SizedBox(width: AcxSpacing.sm),
                      const AcxStatusBadge(label: '当前', status: AcxStatus.success),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AcxColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AcxSpacing.sm),
          if (!current)
            TextButton(
              onPressed: busy ? null : onSwitch,
              child: const Text('切换'),
            ),
          IconButton(
            onPressed: busy ? null : onRemove,
            tooltip: '移除账号',
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: AcxColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

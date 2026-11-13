// 桌面端「窗口与托盘」：点关闭按钮时的行为。
//
// 放在设置里而不是每次弹窗里勾选：这是习惯问题，改一次就该长期生效；
// 「每次询问」是给还没想好的用户留的默认值。
import 'package:flutter/material.dart';

import '../platform/window_shell.dart';
import 'theme.dart';
import 'widgets.dart';

class WindowSettingsPage extends StatefulWidget {
  const WindowSettingsPage({super.key, required this.shell});

  final WindowShell shell;

  @override
  State<WindowSettingsPage> createState() => _WindowSettingsPageState();
}

class _WindowSettingsPageState extends State<WindowSettingsPage> {
  CloseAction? _action;

  @override
  void initState() {
    super.initState();
    widget.shell.readCloseAction().then((CloseAction a) {
      if (mounted) setState(() => _action = a);
    });
  }

  Future<void> _select(CloseAction action) async {
    setState(() => _action = action);
    await widget.shell.writeCloseAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '点关闭按钮时',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AcxColors.textSecondary,
            ),
          ),
          const SizedBox(height: AcxSpacing.md),
          AcxSectionCard(
            padding: const EdgeInsets.symmetric(vertical: AcxSpacing.sm),
            child: Column(
              children: <Widget>[
                _Option(
                  value: CloseAction.ask,
                  groupValue: _action,
                  title: '每次询问',
                  detail: '弹窗问一次：收到托盘还是退出',
                  onSelect: _select,
                ),
                const Divider(height: 1),
                _Option(
                  value: CloseAction.minimizeToTray,
                  groupValue: _action,
                  title: '最小化到托盘',
                  detail: '窗口收起，执行继续跑；从托盘图标点回来',
                  onSelect: _select,
                ),
                const Divider(height: 1),
                _Option(
                  value: CloseAction.exitApp,
                  groupValue: _action,
                  title: '直接退出应用',
                  detail: '结束进程；正在执行的章节会停在当前进度',
                  onSelect: _select,
                ),
              ],
            ),
          ),
          const SizedBox(height: AcxSpacing.lg),
          const Text(
            '收到托盘时进程仍在运行，正在执行的章节不会中断。'
            '想彻底退出请用托盘菜单的「退出」，或在这里选「直接退出应用」。',
            style: TextStyle(fontSize: 12, height: 1.7, color: AcxColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.detail,
    required this.onSelect,
  });

  final CloseAction value;
  final CloseAction? groupValue;
  final String title;
  final String detail;
  final ValueChanged<CloseAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final bool selected = groupValue == value;
    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(AcxRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.lg, vertical: AcxSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AcxColors.brand : AcxColors.textTertiary,
            ),
            const SizedBox(width: AcxSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: AcxColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AcxColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

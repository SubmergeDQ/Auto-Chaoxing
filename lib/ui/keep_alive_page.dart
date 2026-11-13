// 后台保活：把「还差哪一步」讲清楚，并提供一键跳转。
//
// 常见误解是「点了开始就一定会跑到底」。实际上要三件事同时成立：
// 前台服务（通知栏看得见）+ 唤醒锁（熄屏不掐 timer）+ 省电策略无限制（不被冻结）。
// 前两项应用自己做，第三项必须用户点一次，所以这里重点是把第三项摆在明面上。
import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/keep_alive_settings.dart';
import 'theme.dart';
import 'widgets.dart';

class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key, required this.settings});

  final KeepAliveSettings settings;

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage> {
  bool? _notifications;
  bool? _unrestricted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final bool n = await widget.settings.hasNotificationPermission();
    final bool u = await widget.settings.isUnrestricted();
    if (!mounted) return;
    setState(() {
      _notifications = n;
      _unrestricted = u;
    });
  }

  Future<void> _askNotifications() async {
    setState(() => _busy = true);
    await widget.settings.requestNotificationPermission();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _askUnrestricted() async {
    setState(() => _busy = true);
    final bool granted = await widget.settings.requestUnrestricted();
    // 系统弹窗是异步的：用户点完回来这里才拿得到最终状态，
    // 所以先刷新一次；没拿到就引导去列表页手动开。
    await _refresh();
    if (!granted && mounted) {
      await widget.settings.openBatterySettings();
      await _refresh();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '执行期间应用会挂一个前台服务并持有唤醒锁，熄屏不会中断。'
            '下面两项决定系统会不会在后台把它冻结——建议都打开。',
            style: TextStyle(fontSize: 12, height: 1.7, color: AcxColors.textSecondary),
          ),
          const SizedBox(height: AcxSpacing.xl),
          _StepCard(
            index: 1,
            title: '通知栏常驻',
            ok: _notifications,
            detail: '通知既是进度条，也是「停止」按钮的入口。没有它，服务照跑但你看不到状态。',
            actionLabel: '允许通知',
            onAction: _busy ? null : () => unawaited(_askNotifications()),
          ),
          const SizedBox(height: AcxSpacing.md),
          _StepCard(
            index: 2,
            title: '省电策略设为「无限制」',
            ok: _unrestricted,
            detail: '默认策略会在锁屏后限制后台网络与计时，表现为进度上报变慢甚至停住。',
            actionLabel: '去设置',
            onAction: _busy ? null : () => unawaited(_askUnrestricted()),
          ),
          const SizedBox(height: AcxSpacing.xl),
          const _InfoCard(
            title: '唤醒锁',
            text: '执行开始时自动持有，结束时释放，不需要单独设置。'
                '它的作用只是让 CPU 别在熄屏后立刻睡下去，替代不了上面两项。',
          ),
          const SizedBox(height: AcxSpacing.md),
          const _InfoCard(
            title: '再多一层：在最近任务里锁定',
            text: '打开多任务界面，把本应用卡片向下拉（或长按）选择「锁定」，'
                '系统清理后台时就会跳过它。这一步因机型而异，没有统一样式。',
          ),
          const SizedBox(height: AcxSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新检测'),
              style: TextButton.styleFrom(foregroundColor: AcxColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.ok,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final int index;
  final String title;
  final bool? ok;
  final String detail;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AcxStatus status = switch (ok) {
      true => AcxStatus.success,
      false => AcxStatus.attention,
      null => AcxStatus.idle,
    };
    final String label = switch (ok) {
      true => '已开启',
      false => '未开启',
      null => '检测中',
    };

    return AcxSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AcxColors.brandSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: AcxSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.textPrimary,
                  ),
                ),
              ),
              AcxStatusBadge(label: label, status: status),
            ],
          ),
          const SizedBox(height: AcxSpacing.md),
          Text(
            detail,
            style: const TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
          ),
          if (ok != true) ...<Widget>[
            const SizedBox(height: AcxSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AcxSectionCard(
      padding: const EdgeInsets.all(AcxSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_outline_rounded, size: 16, color: AcxColors.textTertiary),
          const SizedBox(width: AcxSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AcxColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

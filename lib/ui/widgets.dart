// 共享组件：先在代表页固定导航、卡片、状态与反馈的必要变体，其他页面复用同一套。
import 'package:flutter/material.dart';

import 'theme.dart';

class AcxStatusBadge extends StatelessWidget {
  const AcxStatusBadge({
    super.key,
    required this.label,
    required this.status,
  });

  final String label;
  final AcxStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = AcxStatusStyle.foreground(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AcxStatusStyle.background(status),
        borderRadius: BorderRadius.circular(AcxRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(AcxStatusStyle.icon(status), size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

class AcxSectionCard extends StatelessWidget {
  const AcxSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AcxSpacing.xl),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: padding, child: child));
  }
}

class AcxEmptyState extends StatelessWidget {
  const AcxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AcxSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AcxColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AcxColors.brand),
            ),
            const SizedBox(height: AcxSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AcxColors.textPrimary,
              ),
            ),
            const SizedBox(height: AcxSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.6, color: AcxColors.textSecondary),
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AcxSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class AcxErrorState extends StatelessWidget {
  const AcxErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = '没能取到数据',
  });

  final String message;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AcxSectionCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.error_outline_rounded, color: AcxColors.danger, size: 20),
                  const SizedBox(width: AcxSpacing.sm),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AcxColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AcxSpacing.md),
              Text(
                message,
                style: const TextStyle(fontSize: 13, height: 1.6, color: AcxColors.textSecondary),
              ),
              const SizedBox(height: AcxSpacing.xl),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AcxMetric extends StatelessWidget {
  const AcxMetric({
    super.key,
    required this.label,
    required this.value,
    this.accent = AcxColors.textPrimary,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: accent,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
        ),
      ],
    );
  }
}

class AcxAccountChip extends StatelessWidget {
  const AcxAccountChip({super.key, required this.name, required this.signedIn});

  final String name;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: signedIn ? AcxColors.brandSoft : AcxColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AcxRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            signedIn ? Icons.account_circle_outlined : Icons.person_off_outlined,
            size: 16,
            color: signedIn ? AcxColors.brand : AcxColors.textTertiary,
          ),
          const SizedBox(width: AcxSpacing.sm),
          Text(
            signedIn ? name : '未连接账号',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: signedIn ? AcxColors.brand : AcxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 紧凑单行顶栏：把标题、实时状态与全局动作合在一排，不叠双层 AppBar。
class AcxTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AcxTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.xl),
      decoration: const BoxDecoration(
        color: AcxColors.surface,
        border: Border(bottom: BorderSide(color: AcxColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AcxSpacing.lg),
          ...actions,
        ],
      ),
    );
  }
}

// 关于页：版本、仓库地址、检查更新。
//
// 更新入口放在关于里而不是一级导航：它一年用不到几次，但要一眼能找到。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update/app_release.dart';
import '../core/update/update_checker.dart';
import '../core/version.dart';
import '../state/update_state.dart';
import 'theme.dart';
import 'widgets.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.update});

  final UpdateState update;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: update,
      builder: (BuildContext context, Widget? _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AcxSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _AppHeader(),
              const SizedBox(height: AcxSpacing.xxl),
              _RepoCard(),
              const SizedBox(height: AcxSpacing.xxl),
              const Text(
                '更新',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AcxColors.textSecondary,
                ),
              ),
              const SizedBox(height: AcxSpacing.md),
              _UpdateCard(update: update),
            ],
          ),
        );
      },
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AcxColors.brand,
            borderRadius: BorderRadius.circular(AcxRadius.md),
          ),
          child: const Icon(Icons.auto_stories_rounded, size: 26, color: Colors.white),
        ),
        const SizedBox(width: AcxSpacing.lg),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Auto-Chaoxing',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AcxColors.textPrimary,
                ),
              ),
              SizedBox(height: 3),
              Text(
                '学习通课程自动化客户端',
                style: TextStyle(fontSize: 12, color: AcxColors.textSecondary),
              ),
            ],
          ),
        ),
        AcxStatusBadge(label: kAppVersionLabel, status: AcxStatus.idle),
      ],
    );
  }
}

class _RepoCard extends StatelessWidget {
  Future<void> _open() async {
    final Uri uri = Uri.parse(kRepoUrl);
    try {
      final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launcher refused');
    } catch (_) {
      // 没有浏览器 / 被策略拦：退一步把地址复制走，用户自己粘到浏览器。
      await _copy(kRepoUrl);
    }
  }

  static Future<void> _copy(String text) async {
    // 不 await：剪贴板通道在部分环境不回消息，await 会把界面挂住。
    // ignore: unawaited_futures
    Clipboard.setData(ClipboardData(text: text)).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    return AcxSectionCard(
      padding: const EdgeInsets.all(AcxSpacing.lg),
      child: Row(
        children: <Widget>[
          const Icon(Icons.code_rounded, size: 18, color: AcxColors.brand),
          const SizedBox(width: AcxSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '开源仓库',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AcxColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                SelectableText(
                  kRepoUrl,
                  style: TextStyle(fontSize: 12, color: AcxColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AcxSpacing.md),
          OutlinedButton(
            onPressed: () => unawaited(_open()),
            child: const Text('打开发行版'),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.update});

  final UpdateState update;

  @override
  Widget build(BuildContext context) {
    final UpdatePhase phase = update.phase;
    final bool busy = phase == UpdatePhase.checking || phase == UpdatePhase.downloading;
    final AcxStatus status = switch (phase) {
      UpdatePhase.idle => AcxStatus.idle,
      UpdatePhase.checking => AcxStatus.running,
      UpdatePhase.upToDate => AcxStatus.success,
      UpdatePhase.available => AcxStatus.attention,
      UpdatePhase.downloading => AcxStatus.running,
      UpdatePhase.ready => AcxStatus.success,
      UpdatePhase.failed => AcxStatus.failed,
    };
    final String label = switch (phase) {
      UpdatePhase.idle => '未检查',
      UpdatePhase.checking => '检查中',
      UpdatePhase.upToDate => '已是最新',
      UpdatePhase.available => '有新版本',
      UpdatePhase.downloading => '下载中',
      UpdatePhase.ready => '可以安装',
      UpdatePhase.failed => '检查失败',
    };

    final AppRelease? latest = update.latest;
    final ReleaseAsset? asset = update.targetAsset;

    return AcxSectionCard(
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
                      '当前版本 $kAppVersionLabel',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AcxColors.textPrimary,
                      ),
                    ),
                    if (update.message != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        update.message!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: phase == UpdatePhase.failed
                              ? AcxColors.danger
                              : AcxColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AcxSpacing.md),
              AcxStatusBadge(label: label, status: status),
            ],
          ),
          if (phase == UpdatePhase.downloading) ...<Widget>[
            const SizedBox(height: AcxSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(AcxRadius.sm),
              child: LinearProgressIndicator(
                value: update.progress,
                minHeight: 4,
                backgroundColor: AcxColors.border,
                valueColor: const AlwaysStoppedAnimation<Color>(AcxColors.brand),
              ),
            ),
            const SizedBox(height: AcxSpacing.sm),
            Text(
              update.progress == null
                  ? '正在下载…'
                  : '已下载 ${(update.progress! * 100).toStringAsFixed(0)}%'
                      '${asset != null && asset.size > 0 ? ' · ${asset.sizeLabel}' : ''}',
              style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
            ),
          ],
          if (phase == UpdatePhase.available && latest != null) ...<Widget>[
            const SizedBox(height: AcxSpacing.lg),
            _ReleaseNotes(
              version: latest.version,
              notes: latest.notes,
              assetName: asset?.name,
              assetSize: asset?.sizeLabel ?? '',
            ),
          ],
          const SizedBox(height: AcxSpacing.lg),
          Wrap(
            spacing: AcxSpacing.md,
            runSpacing: AcxSpacing.sm,
            children: <Widget>[
              switch (phase) {
                UpdatePhase.downloading => OutlinedButton(
                    onPressed: update.cancelDownload,
                    child: const Text('取消下载'),
                  ),
                UpdatePhase.available => FilledButton.icon(
                    onPressed: () => unawaited(update.downloadAndInstall()),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(asset == null ? '下载安装包' : '下载并安装'),
                  ),
                _ => FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => unawaited(update.checkForUpdates(force: true)),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(phase == UpdatePhase.checking ? '检查中…' : '检查更新'),
                  ),
              },
              if (phase != UpdatePhase.available && phase != UpdatePhase.downloading)
                TextButton(
                  onPressed: () => unawaited(launchUrl(
                    Uri.parse('$kRepoUrl/releases/latest'),
                    mode: LaunchMode.externalApplication,
                  ).catchError((Object _) => false)),
                  child: const Text('打开发行版页面'),
                ),
            ],
          ),
          if (phase == UpdatePhase.ready) ...<Widget>[
            const SizedBox(height: AcxSpacing.md),
            const Text(
              'Android：系统安装界面会盖在应用上，按提示覆盖安装即可。'
              'Windows：安装程序已启动，本应用会退出以便替换文件。',
              style: TextStyle(fontSize: 12, height: 1.7, color: AcxColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({
    required this.version,
    required this.notes,
    required this.assetName,
    required this.assetSize,
  });

  final String version;
  final String notes;
  final String? assetName;
  final String assetSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AcxSpacing.lg),
      decoration: BoxDecoration(
        color: AcxColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AcxRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '新版本 $version 的说明',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AcxColors.textPrimary,
            ),
          ),
          if (assetName != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '将下载 $assetName${assetSize.isEmpty ? '' : ' · $assetSize'}',
              style: const TextStyle(fontSize: 11, color: AcxColors.textTertiary),
            ),
          ],
          if (notes.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AcxSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  notes.trim(),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: AcxColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

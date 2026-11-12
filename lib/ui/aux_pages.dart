// 协议自检页与运行约束页。
// 自检向量与 core/chaoxing_core.py、test/crypto_test.dart 三者一致。
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/crypto.dart';
import '../state/app_state.dart';
import '../state/keep_alive_probe.dart';
import 'courses_page.dart';
import 'theme.dart';
import 'widgets.dart';

class SelfCheckPage extends StatefulWidget {
  const SelfCheckPage({super.key, required this.probe});

  /// 自检的生命周期由 AppState 持有：页面只是显示它。
  /// 这样切页、锁屏回来都不会把已经跑了一半的计时丢掉。
  final KeepAliveProbe probe;

  @override
  State<SelfCheckPage> createState() => _SelfCheckPageState();
}

class _SelfCheckPageState extends State<SelfCheckPage> {
  static const String _aesExpect = '0QgUbMUJj2usHikiqtb8HQ==';
  static const String _encExpect = 'f72245dce1271d7e6039a4f3110a0575';

  KeepAliveProbe get _probe => widget.probe;

  @override
  Widget build(BuildContext context) {
    final String aes = aesCbcBase64('123456');
    final String enc = progressEnc(
      classId: '123',
      uid: '456',
      jobId: '789',
      objectId: 'abc',
      playTime: 0,
      duration: 600,
    );
    final bool aesOk = aes == _aesExpect;
    final bool encOk = enc == _encExpect;
    final bool allOk = aesOk && encOk;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AcxSectionCard(
            child: Row(
              children: <Widget>[
                AcxStatusBadge(
                  label: allOk ? '协议自检通过' : '协议自检异常',
                  status: allOk ? AcxStatus.success : AcxStatus.failed,
                ),
                const SizedBox(width: AcxSpacing.lg),
                const Expanded(
                  child: Text(
                    '以下两项用于确认当前客户端的登录加密与进度签名实现正确。任一项失败时请停止自动化任务，更新客户端后再试。',
                    style: TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AcxSpacing.lg),
          _VectorCard(
            label: 'AES-CBC 登录加密',
            detail: 'aesCbcBase64("123456")',
            actual: aes,
            expected: _aesExpect,
            ok: aesOk,
          ),
          const SizedBox(height: AcxSpacing.md),
          _VectorCard(
            label: '视频进度签名',
            detail: 'progressEnc(0s / 600s)',
            actual: enc,
            expected: _encExpect,
            ok: encOk,
          ),
          const SizedBox(height: AcxSpacing.xl),
          const Text(
            '自检只在本机计算，不发送任何请求；结果由当前客户端实际运行得出，未执行时不会显示通过。',
            style: TextStyle(fontSize: 12, height: 1.7, color: AcxColors.textTertiary),
          ),
          if (_probe.supported) ...<Widget>[
            const SizedBox(height: AcxSpacing.xxl),
            const Text(
              '运行环境',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AcxColors.textSecondary,
              ),
            ),
            const SizedBox(height: AcxSpacing.md),
            AnimatedBuilder(
              animation: _probe,
              builder: (BuildContext context, Widget? _) => _KeepAliveCard(probe: _probe),
            ),
          ],
        ],
      ),
    );
  }
}

/// 后台保活自检。纯本地计时，用来判断熄屏后系统有没有把计时押后。
class _KeepAliveCard extends StatelessWidget {
  const _KeepAliveCard({required this.probe});

  final KeepAliveProbe probe;

  @override
  Widget build(BuildContext context) {
    final ProbePhase phase = probe.phase;
    final AcxStatus badge = switch (phase) {
      ProbePhase.idle => AcxStatus.idle,
      ProbePhase.running => AcxStatus.running,
      ProbePhase.done => probe.continuous ? AcxStatus.success : AcxStatus.attention,
    };
    final String label = switch (phase) {
      ProbePhase.idle => '未开始',
      ProbePhase.running => '计时中',
      ProbePhase.done => probe.continuous ? '计时连续' : '计时被押后',
    };

    return AcxSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '后台保活',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AcxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phase == ProbePhase.idle
                          ? '熄屏后计时还在不在走。点开始后锁屏 ${probe.total.inMinutes} 分钟再回来，看心跳是否连贯。'
                          : _detail(phase),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: AcxColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AcxSpacing.lg),
              AcxStatusBadge(label: label, status: badge),
            ],
          ),
          if (phase != ProbePhase.idle) ...<Widget>[
            const SizedBox(height: AcxSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(AcxRadius.sm),
              child: LinearProgressIndicator(
                value: _ratio,
                minHeight: 4,
                backgroundColor: AcxColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  phase == ProbePhase.done && !probe.continuous
                      ? AcxColors.warning
                      : AcxColors.brand,
                ),
              ),
            ),
            const SizedBox(height: AcxSpacing.sm),
            Text(
              '${_clock(probe.elapsed)} / ${_clock(probe.total)} · '
              '心跳 ${probe.ticks} 次 · 最长间隔 ${probe.maxGap.inSeconds} 秒',
              style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
            ),
          ],
          if (phase == ProbePhase.done) ...<Widget>[
            const SizedBox(height: AcxSpacing.md),
            Text(
              probe.verdict,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
                color: probe.continuous ? AcxColors.success : AcxColors.warning,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '这个结果只说明计时有没有被打断：刚才若真的熄屏过，说明前台服务与唤醒锁生效；'
              '若全程亮屏，它只证明前台计时正常，不代表熄屏可用。',
              style: TextStyle(fontSize: 12, height: 1.7, color: AcxColors.textTertiary),
            ),
          ],
          const SizedBox(height: AcxSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: switch (phase) {
              ProbePhase.idle => FilledButton(
                  onPressed: () => unawaited(probe.start()),
                  child: const Text('开始自检'),
                ),
              ProbePhase.running => OutlinedButton(
                  onPressed: () => unawaited(probe.stop()),
                  child: const Text('停止自检'),
                ),
              ProbePhase.done => TextButton.icon(
                  onPressed: () => unawaited(probe.start()),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新自检'),
                  style: TextButton.styleFrom(foregroundColor: AcxColors.textSecondary),
                ),
            },
          ),
        ],
      ),
    );
  }

  double get _ratio {
    final int total = probe.total.inSeconds;
    if (total <= 0) return 0;
    final double r = probe.elapsed.inSeconds / total;
    return r.clamp(0, 1);
  }

  String _detail(ProbePhase phase) {
    if (phase == ProbePhase.running) {
      return probe.keeping
          ? '已挂上前台服务与唤醒锁，现在可以锁屏。'
          : '保活没有起来，这次熄屏后计时很可能会被暂停。';
    }
    return '自检结束。每次心跳间隔 ${probe.step.inSeconds} 秒，超过 ${probe.step.inSeconds * 2} 秒就算中断。';
  }

  static String _clock(Duration d) {
    final int s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _VectorCard extends StatelessWidget {
  const _VectorCard({
    required this.label,
    required this.detail,
    required this.actual,
    required this.expected,
    required this.ok,
  });

  final String label;
  final String detail;
  final String actual;
  final String expected;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return AcxSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AcxColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
                    ),
                  ],
                ),
              ),
              AcxStatusBadge(
                label: ok ? '通过' : '未通过',
                status: ok ? AcxStatus.success : AcxStatus.failed,
              ),
            ],
          ),
          const SizedBox(height: AcxSpacing.lg),
          _ValueLine(label: '实际值', value: actual),
          const SizedBox(height: AcxSpacing.sm),
          _ValueLine(label: '期望值', value: expected),
        ],
      ),
    );
  }
}

class _ValueLine extends StatelessWidget {
  const _ValueLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AcxColors.textTertiary),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 12, color: AcxColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '运行约束',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AcxColors.textSecondary),
          ),
          const SizedBox(height: AcxSpacing.md),
          const AcxSectionCard(
            padding: EdgeInsets.symmetric(horizontal: AcxSpacing.xl, vertical: AcxSpacing.sm),
            child: Column(
              children: <Widget>[
                _SettingRow(
                  icon: Icons.linear_scale_rounded,
                  title: '单账号串行',
                  detail: '同一时间只跑一个任务，避免并发触发风控',
                ),
                Divider(height: 1),
                _SettingRow(
                  icon: Icons.speed_rounded,
                  title: '节流间隔',
                  detail: '答题 2–4 秒 · 进度 1 秒 · 课程 30 秒',
                ),
                Divider(height: 1),
                _SettingRow(
                  icon: Icons.no_adult_content_outlined,
                  title: '考试功能',
                  detail: '只提醒，不自动交卷',
                ),
                Divider(height: 1),
                _SettingRow(
                  icon: Icons.front_hand_outlined,
                  title: '需要人工时停止',
                  detail: '人脸抽检、验证码、二次验证一律交回用户处理',
                ),
              ],
            ),
          ),
          const SizedBox(height: AcxSpacing.xl),
          const Text(
            '隐私',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AcxColors.textSecondary),
          ),
          const SizedBox(height: AcxSpacing.md),
          const AcxSectionCard(
            padding: EdgeInsets.symmetric(horizontal: AcxSpacing.xl, vertical: AcxSpacing.sm),
            child: Column(
              children: <Widget>[
                _SettingRow(
                  icon: Icons.shield_outlined,
                  title: '日志脱敏',
                  detail: '不记录密码、cookie 原文、手机号、姓名与学号',
                ),
                Divider(height: 1),
                _SettingRow(
                  icon: Icons.computer_rounded,
                  title: '本地请求',
                  detail: '所有请求从本机直接发出，不经第三方中转',
                ),
              ],
            ),
          ),
          const SizedBox(height: AcxSpacing.xl),
          const Text(
            '账号',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AcxColors.textSecondary),
          ),
          const SizedBox(height: AcxSpacing.md),
          AcxSectionCard(
            child: Row(
              children: <Widget>[
                Icon(
                  state.signedIn ? Icons.account_circle_outlined : Icons.person_off_outlined,
                  color: state.signedIn ? AcxColors.brand : AcxColors.textTertiary,
                ),
                const SizedBox(width: AcxSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        state.signedIn ? (state.profile?.name ?? '已连接') : '未连接账号',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AcxColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.signedIn
                            ? '${state.profile?.school ?? "学校未填写"}  ·  uid ${state.profile?.uid ?? ""}'
                            : '连接账号后即可读取课程与章节',
                        style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                // 断开后留在设置页也要能就地重连，不必自己想到切回工作台。
                if (state.signedIn)
                  OutlinedButton(
                    onPressed: () => unawaited(state.signOut()),
                    child: const Text('断开连接'),
                  )
                else
                  FilledButton(
                    onPressed: () => unawaited(
                      showDialog<void>(
                        context: context,
                        builder: (BuildContext _) => LoginDialog(state: state),
                      ),
                    ),
                    child: const Text('连接账号'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AcxSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AcxColors.brand),
          const SizedBox(width: AcxSpacing.lg),
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
                  detail,
                  style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

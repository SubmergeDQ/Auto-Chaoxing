// 平台能力抽象：Android 与 Windows 的差异只允许出现在这一层。
//
// 约定：
//   · 业务层（lib/core/**）禁止 import dart:io 平台判断，也禁止 import 本文件以外的平台插件；
//   · 所有平台差异通过下面的接口暴露，注入到业务层；
//   · 具体实现分别在 lib/platform/android_*.dart 与 lib/platform/windows_*.dart（M3 阶段补齐）。
import 'dart:async';

/// 后台长任务。Android 用前台服务；Windows 用普通 Isolate。
abstract class BackgroundRunner {
  /// 开始任务；[tick] 每次被调用时应返回 true 表示继续运行。
  Future<void> start({
    required String title,
    required String body,
    required Future<bool> Function(void Function(String) report) tick,
  });

  Future<void> stop();

  bool get isRunning;
}

/// 通知。Android 用系统通知；Windows 用托盘气泡 / 应用内提示。
abstract class Notifier {
  Future<void> init();
  Future<void> show({required String title, required String body, String? tag});
}

/// 内嵌浏览器，仅用于登录兜底与（Android）作业提交。
abstract class WebAuth {
  bool get supportsScriptInjection;

  /// 打开登录页，等用户登录完成后把 cookie 交回来。
  Future<Map<String, String>> loginInteractive(Uri url, {Duration timeout = const Duration(minutes: 5)});

  /// 仅在 [supportsScriptInjection] 为 true 时可用。
  Future<String?> evaluateJavascript(String script);
}

/// 凭据存储。Android 走 Keystore，Windows 走 DPAPI。
abstract class SecretStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// 平台能力集合。业务层只依赖这个容器。
class PlatformServices {
  const PlatformServices({
    required this.background,
    required this.notifier,
    required this.web,
    required this.secrets,
  });

  final BackgroundRunner background;
  final Notifier notifier;
  final WebAuth web;
  final SecretStore secrets;
}

/// 尚未实现的占位：显式抛出而不是静默空转，避免"看起来跑了其实没跑"。
class UnimplementedBackgroundRunner implements BackgroundRunner {
  @override
  Future<void> start({
    required String title,
    required String body,
    required Future<bool> Function(void Function(String) report) tick,
  }) =>
      throw UnsupportedError('后台服务尚未接入（M3 阶段实现）');

  @override
  Future<void> stop() async {}

  @override
  bool get isRunning => false;
}

class UnimplementedWebAuth implements WebAuth {
  @override
  bool get supportsScriptInjection => false;

  @override
  Future<Map<String, String>> loginInteractive(Uri url,
          {Duration timeout = const Duration(minutes: 5)}) =>
      throw UnsupportedError('内嵌浏览器尚未接入（M1 阶段实现）');

  @override
  Future<String?> evaluateJavascript(String script) =>
      throw UnsupportedError('当前平台不支持脚本注入');
}

// 平台能力抽象：Android 与 Windows 的差异只允许出现在这一层。
//
// 约定：
//   · 业务层（lib/core/**）禁止 import dart:io 平台判断，也禁止 import 本文件以外的平台插件；
//   · 所有平台差异通过下面的接口暴露，注入到业务层；
//   · 具体实现分别在 lib/platform/*_android.dart 与 Noop（Windows 用不到）。
import 'dart:async';

/// 执行期间的「后台保活」。
///
/// 为什么不是「把任务搬到后台 isolate」：上报节奏靠 Dart 的 60 秒节流，
/// 节流依赖本地定时器。只要进程活着、CPU 不进深度睡眠，定时器就会照常到期，
/// 所以这里不做任务搬运，只做两件事——
///   1) 把进程提到前台服务的优先级，避免切后台后被按「后台应用」回收；
///   2) 持一把 PARTIAL_WAKE_LOCK，熄屏后 CPU 不被 Doze 拖慢或停摆。
///
/// 失败一律**不抛异常**：拿不到通知权限、服务起不来，执行也该继续跑，
/// 只是退化成「切后台可能被系统暂停」。调用方据返回值决定是否如实告知用户。
abstract class RunKeeper {
  /// 当前平台是否提供保活。Windows 窗口最小化本来就不冻结进程，返回 false。
  bool get supported;

  /// 确保能显示常驻通知（Android 13+ 需运行时授权）。
  /// 返回 false 表示用户拒绝：执行照旧，但通知栏看不到进度与「停止」。
  Future<bool> ensureNotificationPermission();

  Future<bool> begin({required String title, required String body});

  Future<void> update({required String title, required String body});

  /// 执行结束：把通知换成最终结果并撤离前台。
  /// 用户切回应用之前，通知栏是他唯一能知道「跑完了 / 卡住了」的地方。
  Future<void> finish({required String title, required String body});

  /// 主动结束保活（用户点「停止执行」/ 断开账号），连同通知一起撤掉。
  Future<void> end();

  /// 用户在系统通知上点「停止」。
  Stream<void> get stopRequests;

  void dispose();
}

/// 不提供保活的平台，以及所有测试环境。
class NoopRunKeeper implements RunKeeper {
  const NoopRunKeeper();

  @override
  bool get supported => false;

  @override
  Future<bool> ensureNotificationPermission() async => true;

  @override
  Future<bool> begin({required String title, required String body}) async => false;

  @override
  Future<void> update({required String title, required String body}) async {}

  @override
  Future<void> finish({required String title, required String body}) async {}

  @override
  Future<void> end() async {}

  @override
  Stream<void> get stopRequests => const Stream<void>.empty();

  @override
  void dispose() {}
}

/// 通知。Android 用系统通知；Windows 用托盘气泡 / 应用内提示。（尚未接入）
abstract class Notifier {
  Future<void> init();
  Future<void> show({required String title, required String body, String? tag});
}

/// 内嵌浏览器，仅用于登录兜底与（Android）作业提交。（尚未接入）
abstract class WebAuth {
  bool get supportsScriptInjection;

  /// 打开登录页，等用户登录完成后把 cookie 交回来。
  Future<Map<String, String>> loginInteractive(Uri url,
      {Duration timeout = const Duration(minutes: 5)});

  /// 仅在 [supportsScriptInjection] 为 true 时可用。
  Future<String?> evaluateJavascript(String script);
}

/// 凭据存储。Android 走 Keystore，Windows 走 DPAPI。（尚未接入）
abstract class SecretStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// 平台能力集合。业务层只依赖这个容器。
class PlatformServices {
  const PlatformServices({
    required this.runKeeper,
    required this.notifier,
    required this.web,
    required this.secrets,
  });

  final RunKeeper runKeeper;
  final Notifier notifier;
  final WebAuth web;
  final SecretStore secrets;
}

class UnimplementedWebAuth implements WebAuth {
  @override
  bool get supportsScriptInjection => false;

  @override
  Future<Map<String, String>> loginInteractive(Uri url,
          {Duration timeout = const Duration(minutes: 5)}) =>
      throw UnsupportedError('内嵌浏览器尚未接入（M3 阶段实现）');

  @override
  Future<String?> evaluateJavascript(String script) =>
      throw UnsupportedError('当前平台不支持脚本注入');
}

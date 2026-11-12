// Android 侧的后台保活实现：MethodChannel 到原生 RunKeepService。
//
// 通道方法：
//   begin   {title, body} → bool   起前台服务并持 wakelock；没通知权限时返回 false
//   update  {title, body}          只刷新通知文案
//   end                            停服务（Dart 主动结束，不回调）
//   ensureNotificationPermission → bool    Android 13+ 运行时授权
// 反向方法：
//   onStopRequested                用户在通知上点「停止」
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_services.dart';

/// 按平台挑选实现。测试与业务默认拿到 Noop，只有 AppState 显式注入真实实现。
RunKeeper createRunKeeper() {
  if (kIsWeb) return const NoopRunKeeper();
  if (defaultTargetPlatform == TargetPlatform.android) return AndroidRunKeeper();
  return const NoopRunKeeper();
}

class AndroidRunKeeper implements RunKeeper {
  AndroidRunKeeper() {
    // 没有 WidgetsBinding 时（例如纯 Dart 单测里直接 new AppState）注册 handler
    // 会断言失败。那种环境本来也收不到回传，跳过即可，不该让构造抛异常。
    try {
      _channel.setMethodCallHandler(_handle);
      _bound = true;
    } catch (_) {
      _bound = false;
    }
  }

  static const MethodChannel _channel = MethodChannel('cn.autochaoxing/run_keeper');

  final StreamController<void> _stops = StreamController<void>.broadcast();
  bool _disposed = false;
  bool _bound = false;

  @override
  bool get supported => true;

  @override
  Stream<void> get stopRequests => _stops.stream;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'onStopRequested' && !_disposed) _stops.add(null);
    return null;
  }

  @override
  Future<bool> ensureNotificationPermission() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('ensureNotificationPermission');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> begin({required String title, required String body}) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('begin', <String, String>{
        'title': title,
        'body': body,
      });
      return ok ?? false;
    } on MissingPluginException {
      // 通道没注册：测试环境，或者原生侧被裁掉了。不当作错误，按「没保活」处理。
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> update({required String title, required String body}) async {
    try {
      await _channel.invokeMethod<void>('update', <String, String>{
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      // 通知只是信息展示，刷不新不该影响执行。
    } on PlatformException {
      // 同上。
    }
  }

  @override
  Future<void> end() async {
    try {
      await _channel.invokeMethod<void>('end');
    } on MissingPluginException {
      // 忽略。
    } on PlatformException {
      // 忽略。
    }
  }

  @override
  Future<void> finish({required String title, required String body}) async {
    try {
      await _channel.invokeMethod<void>('finish', <String, String>{
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      // 忽略：没有原生实现时，结果只能回应用里看，不影响执行。
    } on PlatformException {
      // 忽略。
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_bound) {
      _channel.setMethodCallHandler(null);
      _bound = false;
    }
    _stops.close();
  }
}

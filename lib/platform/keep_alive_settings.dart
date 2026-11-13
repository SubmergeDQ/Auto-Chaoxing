// 保活相关的系统状态与引导入口。
//
// 「保活」在这里不是一件事，而是三件叠加起来的：
//   1) 通知常驻（前台服务）——让系统知道这个进程在做用户可见的事；
//   2) WakeLock —— 熄屏后 CPU 不被 Doze 立刻掐掉；
//   3) 省电策略「无限制」—— 系统不因「后台耗电」把进程冻结。
// 前两项在执行期间由 RunKeepService 自动持有，第三项只能引导用户手动开，
// 所以这个页面主要价值是告诉用户「还差哪一步」。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class KeepAliveSettings {
  /// 当前平台是否有这套东西。Windows 最小化不冻结进程，返回 false。
  bool get supported;

  /// 通知权限。Android 13+ 需要运行时授权。
  Future<bool> hasNotificationPermission();

  /// 弹出系统授权。
  Future<bool> requestNotificationPermission();

  /// 是否已被排除在电池优化之外。
  Future<bool> isUnrestricted();

  /// 申请「无限制」。部分 ROM 会直接弹窗，部分只会跳到列表页。
  Future<bool> requestUnrestricted();

  /// 打开电池优化列表，让用户手动找本应用。
  Future<void> openBatterySettings();
}

KeepAliveSettings createKeepAliveSettings() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidKeepAliveSettings();
  }
  return const NoopKeepAliveSettings();
}

class AndroidKeepAliveSettings implements KeepAliveSettings {
  static const MethodChannel _system = MethodChannel('cn.autochaoxing/system');

  /// 通知权限走 run_keeper 通道（那边已经有完整的权限请求与回传逻辑）。
  static const MethodChannel _keeper = MethodChannel('cn.autochaoxing/run_keeper');

  @override
  bool get supported => true;

  @override
  Future<bool> hasNotificationPermission() async {
    try {
      return (await _system.invokeMethod<bool>('hasNotificationPermission')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      return (await _keeper.invokeMethod<bool>('ensureNotificationPermission')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> isUnrestricted() async {
    try {
      return (await _system.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestUnrestricted() async {
    try {
      return (await _system.invokeMethod<bool>('requestIgnoreBatteryOptimizations')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openBatterySettings() async {
    try {
      await _system.invokeMethod<void>('openBatterySettings');
    } on PlatformException {
      // 打不开就靠用户自己去设置里找。
    }
  }
}

class NoopKeepAliveSettings implements KeepAliveSettings {
  const NoopKeepAliveSettings();

  @override
  bool get supported => false;

  @override
  Future<bool> hasNotificationPermission() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<bool> isUnrestricted() async => true;

  @override
  Future<bool> requestUnrestricted() async => true;

  @override
  Future<void> openBatterySettings() async {}
}

/// 桌面端判断「是不是 Windows」，避免 UI 里散落 Platform.isWindows。
bool get isDesktopWindows =>
    !kIsWeb && (Platform.isWindows || defaultTargetPlatform == TargetPlatform.windows);

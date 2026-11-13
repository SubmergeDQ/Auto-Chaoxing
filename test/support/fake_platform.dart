// 保活设置与窗口外壳的测试替身：只记状态，不碰原生通道。
import 'dart:async';

import 'package:auto_chaoxing/platform/keep_alive_settings.dart';
import 'package:auto_chaoxing/platform/window_shell.dart';

class KeepAliveSettingsStub implements KeepAliveSettings {
  KeepAliveSettingsStub({
    this.supported = true,
    this.notifications = false,
    this.unrestricted = false,
  });

  @override
  final bool supported;

  bool notifications;
  bool unrestricted;

  /// 申请「无限制」的返回值。false 用来模拟系统只跳列表页、不给弹窗。
  bool requestResult = true;

  int notificationRequests = 0;
  int unrestrictedRequests = 0;
  int batterySettingsOpened = 0;

  @override
  Future<bool> hasNotificationPermission() async => notifications;

  @override
  Future<bool> requestNotificationPermission() async {
    notificationRequests++;
    notifications = true;
    return true;
  }

  @override
  Future<bool> isUnrestricted() async => unrestricted;

  @override
  Future<bool> requestUnrestricted() async {
    unrestrictedRequests++;
    return requestResult;
  }

  @override
  Future<void> openBatterySettings() async {
    batterySettingsOpened++;
  }
}

class WindowShellStub implements WindowShell {
  WindowShellStub({this.supported = true, this.action = CloseAction.ask});

  @override
  final bool supported;

  CloseAction action;

  int initCalls = 0;
  int hideCalls = 0;
  int showCalls = 0;
  int quitCalls = 0;

  final StreamController<void> _close = StreamController<void>.broadcast();
  final StreamController<String> _tray = StreamController<String>.broadcast();

  @override
  Future<void> init() async {
    initCalls++;
  }

  @override
  Future<CloseAction> readCloseAction() async => action;

  @override
  Future<void> writeCloseAction(CloseAction value) async {
    action = value;
  }

  @override
  Stream<void> get closeRequests => _close.stream;

  @override
  Stream<String> get trayCommands => _tray.stream;

  @override
  Future<void> hideToTray() async {
    hideCalls++;
  }

  @override
  Future<void> showWindow() async {
    showCalls++;
  }

  @override
  Future<void> quit() async {
    quitCalls++;
  }

  @override
  Future<void> dispose() async {
    await _close.close();
    await _tray.close();
  }
}

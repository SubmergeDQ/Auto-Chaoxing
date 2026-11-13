// 桌面窗口与托盘行为。只有 Windows 有实质实现，其他平台是 Noop。
//
// 三件事在这里落地：
//   1) 点关闭按钮时的行为（每次询问 / 最小化到托盘 / 直接退出）；
//   2) 托盘图标与右键菜单（显示主窗口 / 退出）；
//   3) 真正退出进程（窗口 hide 不等于进程结束，安装更新前必须真的退）。

// window_manager 0.6 / tray_manager 0.8 已把主体迁到 nativeapi，0.5.x 形状的 API
// 保留在 legacy 里并标记弃用。整体迁移单独做，这里先容忍弃用提示。
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 0.8.x 把 0.5.x 的 TrayManager/Menu 迁到了 legacy：主入口换成了 nativeapi，
// 这里的托盘菜单仍是老 API 的形状，所以显式走 legacy，等整体迁移再说。
import 'package:tray_manager/legacy.dart' as tray;
import 'package:window_manager/legacy.dart';

/// 关闭按钮的行为。
enum CloseAction {
  /// 每次弹窗问。
  ask,

  /// 直接收到托盘，不退出。
  minimizeToTray,

  /// 直接退出应用。
  exitApp,
}

abstract class WindowShell {
  /// 只有桌面端为 true。
  bool get supported;

  /// 准备窗口与托盘。Windows 上必须在使用前调用一次；其他平台为空实现。
  Future<void> init();

  /// 点关闭按钮时希望做什么（用户可在设置里改）。
  Future<CloseAction> readCloseAction();

  Future<void> writeCloseAction(CloseAction action);

  /// 用户按了关闭按钮，但设置是「每次询问」——由 UI 决定弹什么。
  Stream<void> get closeRequests;

  /// 从托盘菜单来的指令：show / quit。
  Stream<String> get trayCommands;

  Future<void> hideToTray();

  Future<void> showWindow();

  /// 结束进程。Windows 上必须真的 exit，否则 exe 被占用，更新装不进去。
  Future<void> quit();

  Future<void> dispose();
}

class NoopWindowShell implements WindowShell {
  const NoopWindowShell();

  @override
  bool get supported => false;

  @override
  Future<void> init() async {}

  @override
  Future<CloseAction> readCloseAction() async => CloseAction.exitApp;

  @override
  Future<void> writeCloseAction(CloseAction action) async {}

  @override
  Stream<void> get closeRequests => const Stream<void>.empty();

  @override
  Stream<String> get trayCommands => const Stream<String>.empty();

  @override
  Future<void> hideToTray() async {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> quit() async {}

  @override
  Future<void> dispose() async {}
}

/// 按平台挑实现。测试与移动端拿到 Noop。
WindowShell createWindowShell() {
  if (!kIsWeb && Platform.isWindows) return WindowsWindowShell();
  return const NoopWindowShell();
}

const String _kCloseAction = 'close_action';

class WindowsWindowShell extends WindowShell
    with WindowListener, tray.TrayListener {
  final StreamController<void> _close = StreamController<void>.broadcast();
  final StreamController<String> _tray = StreamController<String>.broadcast();

  bool _initialized = false;
  bool _disposed = false;

  @override
  bool get supported => true;

  @override
  Stream<void> get closeRequests => _close.stream;

  @override
  Stream<String> get trayCommands => _tray.stream;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 820),
        minimumSize: Size(900, 600),
        title: 'Auto-Chaoxing · 学习通客户端',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    // 关闭交给 Dart 决定：直接退出会把「最小化到托盘」这个选项做没了。
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await _initTray();
  }

  Future<void> _initTray() async {
    try {
      // tray_manager 只认真实文件路径，先把 asset 落到临时目录。
      final ByteData data = await rootBundle.load('assets/tray.ico');
      final Directory dir = await getTemporaryDirectory();
      final File icon = File('${dir.path}${Platform.pathSeparator}acx_tray.ico');
      await icon.writeAsBytes(data.buffer.asUint8List(), flush: true);

      await tray.trayManager.setIcon(icon.path);
      await tray.trayManager.setToolTip('Auto-Chaoxing');
      await tray.trayManager.setContextMenu(
        tray.Menu(
          items: <tray.MenuItem>[
            tray.MenuItem(
              key: 'show',
              label: '显示主窗口',
              onClick: (tray.MenuItem _) => _emit('show'),
            ),
            tray.MenuItem.separator(),
            tray.MenuItem(
              key: 'quit',
              label: '退出',
              onClick: (tray.MenuItem _) => _emit('quit'),
            ),
          ],
        ),
      );
      tray.trayManager.addListener(this);
    } catch (_) {
      // 托盘起不来不影响主窗口使用，只是关到托盘会变成「看不见」——
      // 所以这里不让关闭行为退化成 hide，由 UI 侧的 supported 正常处理。
    }
  }

  @override
  Future<CloseAction> readCloseAction() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kCloseAction);
      return CloseAction.values.firstWhere(
        (CloseAction a) => a.name == raw,
        orElse: () => CloseAction.ask,
      );
    } catch (_) {
      return CloseAction.ask;
    }
  }

  @override
  Future<void> writeCloseAction(CloseAction action) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCloseAction, action.name);
    } catch (_) {
      // 记不住就下次再问，不是错误。
    }
  }

  @override
  Future<void> hideToTray() async {
    await windowManager.hide();
  }

  @override
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> quit() async {
    // destroy 会绕过 preventClose，是真正的退出路径。
    await windowManager.destroy();
    exit(0);
  }

  // ------------------------------------------------------------ 事件回调

  @override
  void onWindowClose() {
    // 只把「有人按了关闭」抛给 UI，具体怎么做由调用方按设置决定。
    if (!_disposed) _close.add(null);
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  void _emit(String command) {
    if (!_disposed) _tray.add(command);
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    final String? key = menuItem.key;
    if (key != null) _emit(key);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    windowManager.removeListener(this);
    tray.trayManager.removeListener(this);
    try {
      await tray.trayManager.destroy();
    } catch (_) {}
    await _close.close();
    await _tray.close();
  }
}

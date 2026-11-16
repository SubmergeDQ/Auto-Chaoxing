// 应用数据的落盘位置。
//
// Windows 发布版跟着安装目录走：<安装目录>\userdata\。这样用户把程序装到 D 盘，
// 会话与设置也在 D 盘，不会往 C 盘用户目录写东西。
// 不能叫 data/：Flutter 的 Windows 产物已经占用了 data/ 放 app.so 与 flutter_assets。
// 调试与测试仍用系统应用支持目录，避免在 Flutter SDK 或构建产物里留用户数据。
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 解析「随安装位置走」的数据目录。
///
/// 返回 null 表示沿用系统默认位置：
///   · 非 Windows 平台；
///   · 调试 / 测试（kReleaseMode 为 false）；
///   · 安装目录不可写（例如解压到 Program Files），此时回退保证应用能启动。
Future<Directory?> resolveInstallDataDir() async {
  if (!Platform.isWindows || !kReleaseMode) return null;
  try {
    final Directory base = File(Platform.resolvedExecutable).parent;
    final Directory data = Directory('${base.path}${Platform.pathSeparator}userdata');
    if (!await data.exists()) await data.create(recursive: true);
    // 可写性探针：目录存在不代表能写，装在只读位置时要早点回退。
    final File probe = File('${data.path}${Platform.pathSeparator}.write_probe');
    await probe.writeAsString('probe', flush: true);
    await probe.delete();
    return data;
  } catch (_) {
    return null;
  }
}

// 登录会话的落盘。
//
// 为什么要单独一层：ChaoxingApi 的 CookieJar 是纯内存的，进程一退就没了，
// 于是「登录成功 → 关掉 App → 再打开又要输密码」。学习通对频繁登录有风控，
// 这不是体验问题而是可用性问题，所以会话必须落盘。
//
// 只存 cookie，不存密码：cookie 能续期，密码存盘没有任何必要，
// 反而把「泄露一次全丢」的风险留在设备上。
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

/// 会话文件目录名。放在 application support 下，不写公共目录。
const String kSessionDirName = 'session';

/// 一份可落盘的登录会话。
class SessionJar {
  SessionJar(this.jar, this.dir);

  final CookieJar jar;

  /// 会话目录；内存兜底时为 null，此时 purge 只清 cookie。
  final Directory? dir;

  /// 打开落盘的 CookieJar。任何一步失败都退回内存实现，
  /// 绝不因为存储不可用让 App 起不来——大不了这次要重新登录。
  static Future<SessionJar> open({String? overrideDir}) async {
    try {
      final String root = overrideDir ?? (await getApplicationSupportDirectory()).path;
      final Directory dir = Directory('$root${Platform.pathSeparator}$kSessionDirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return SessionJar(
        PersistCookieJar(ignoreExpires: false, storage: FileStorage(dir.path)),
        dir,
      );
    } catch (_) {
      return SessionJar(CookieJar(), null);
    }
  }

  /// 断开连接时把会话抹干净。
  ///
  /// 只清 cookie 不够：文件里残留的 `_uid`、`_d` 就是一份可用的登录票据，
  /// 所以连目录一起删，下次启动按「未登录」处理。
  Future<void> purge() async {
    try {
      await jar.deleteAll();
    } catch (_) {
      // 删不掉就等它过期，不影响当前流程。
    }
    final Directory? d = dir;
    if (d == null) return;
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {
      // 目录被占用时不强删，cookie 内容已经清掉了。
    }
  }
}

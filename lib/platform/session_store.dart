// 登录会话的落盘与多账号隔离。
//
// 为什么要单独一层：ChaoxingApi 的 CookieJar 是纯内存的，进程一退就没了，
// 于是「登录成功 → 关掉 App → 再打开又要输密码」。学习通对频繁登录有风控，
// 这不是体验问题而是可用性问题，所以会话必须落盘。
//
// 多账号的隔离方式是「一个账号一个目录」：
//   <support>/session/<uid>/        该账号的 cookie（FileStorage）
//   <support>/session/.pending/     正在登录的临时目录，成功后整体改名为 <uid>
//   <support>/accounts.json         账号索引（uid / 名称 / 学校 / 上次使用时间）
//
// 索引刻意放在 session 目录外：FileStorage 会把目录里的每个文件当 cookie 存储读，
// 混进一个 JSON 会让它解析失败。
//
// 只存 cookie，不存密码：cookie 能续期，密码存盘没有任何必要。
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

/// 会话文件目录名。放在 application support 下，不写公共目录。
const String kSessionDirName = 'session';

const String _kAccountsFile = 'accounts.json';
const String _kPendingDir = '.pending';

/// 账号索引里的一条记录。不包含密码，也不包含 cookie。
class StoredAccount {
  const StoredAccount({
    required this.uid,
    required this.name,
    this.school = '',
    this.username = '',
    this.lastUsedAt,
  });

  final String uid;
  final String name;
  final String school;

  /// 上次登录用的手机号，只用于预填登录框。
  final String username;

  final DateTime? lastUsedAt;

  StoredAccount copyWith({
    String? name,
    String? school,
    String? username,
    DateTime? lastUsedAt,
  }) =>
      StoredAccount(
        uid: uid,
        name: name ?? this.name,
        school: school ?? this.school,
        username: username ?? this.username,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'name': name,
        'school': school,
        'username': username,
        'lastUsedAt': lastUsedAt?.millisecondsSinceEpoch,
      };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
        uid: '${json['uid'] ?? ''}',
        name: '${json['name'] ?? ''}',
        school: '${json['school'] ?? ''}',
        username: '${json['username'] ?? ''}',
        lastUsedAt: json['lastUsedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['lastUsedAt'] as int)
            : null,
      );
}

/// 一份可落盘的登录会话，支持多个账号目录。
class SessionJar {
  SessionJar(this.jar, this.dir, {Directory? root, Directory? support}) 
      : _root = root,
        _support = support;

  /// 当前生效的 CookieJar。切换账号时整个替换。
  CookieJar jar;

  /// 当前 jar 的存储目录；内存兜底或登录临时态时可能为 null。
  Directory? dir;

  /// session 根目录；存储不可用时为 null（此时退化为单账号内存模式）。
  final Directory? _root;

  /// application support 根目录，账号索引放在这里。
  final Directory? _support;

  /// 打开会话存储。任何一步失败都退回内存实现，
  /// 绝不因为存储不可用让 App 起不来——大不了这次要重新登录。
  static Future<SessionJar> open({String? overrideDir}) async {
    try {
      final String rootPath = overrideDir ?? (await getApplicationSupportDirectory()).path;
      final Directory root = Directory('$rootPath${Platform.pathSeparator}$kSessionDirName');
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      // 首次启动时直接把根目录当作默认账号的存储，兼容旧版单会话文件。
      return SessionJar(
        PersistCookieJar(ignoreExpires: false, storage: FileStorage(root.path)),
        root,
        root: root,
        support: Directory(rootPath),
      );
    } catch (_) {
      return SessionJar(CookieJar(), null);
    }
  }

  bool get supported => _root != null;

  /// 当前会话是否已经指向某个账号子目录（而不是旧版的根目录）。
  bool get isAccountScoped {
    final Directory? root = _root;
    final Directory? current = dir;
    return root != null && current != null && current.path != root.path;
  }

  // ------------------------------------------------------------ 账号索引

  File? get _accountsFile {
    final Directory? support = _support;
    if (support == null) return null;
    return File('${support.path}${Platform.pathSeparator}$_kAccountsFile');
  }

  Future<List<StoredAccount>> loadAccounts() async {
    final File? file = _accountsFile;
    if (file == null || !await file.exists()) return <StoredAccount>[];
    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <StoredAccount>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => StoredAccount.fromJson(m.cast<String, dynamic>()))
          .where((StoredAccount a) => a.uid.isNotEmpty)
          .toList();
    } catch (_) {
      return <StoredAccount>[];
    }
  }

  Future<void> saveAccounts(List<StoredAccount> accounts) async {
    final File? file = _accountsFile;
    if (file == null) return;
    try {
      await file.writeAsString(
        jsonEncode(accounts.map((StoredAccount a) => a.toJson()).toList()),
        flush: true,
      );
    } catch (_) {
      // 记不住索引不影响当前会话，下次启动会退化成「需要重新登录」。
    }
  }

  // ------------------------------------------------------------ 账号目录

  Directory? _accountDir(String uid) {
    final Directory? root = _root;
    if (root == null || uid.isEmpty) return null;
    return Directory('${root.path}${Platform.pathSeparator}$uid');
  }

  Directory? get _pendingDir {
    final Directory? root = _root;
    if (root == null) return null;
    return Directory('${root.path}${Platform.pathSeparator}$_kPendingDir');
  }

  Future<bool> hasCookies(String uid) async {
    final Directory? dir = _accountDir(uid);
    if (dir == null || !await dir.exists()) return false;
    try {
      // FileStorage 把 cookie 放在 <dir>/ie0_ps1/ 这类子目录里，
      // 只看第一层会把「有会话」误判成「没会话」。
      await for (final FileSystemEntity e in dir.list(recursive: true)) {
        if (e is File) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 把当前 jar 切到某个账号的目录。目录不存在时创建（空会话）。
  Future<CookieJar> activate(String uid) async {
    final Directory? dir = _accountDir(uid);
    if (dir == null) return jar;
    if (!await dir.exists()) await dir.create(recursive: true);
    jar = PersistCookieJar(ignoreExpires: false, storage: FileStorage(dir.path));
    this.dir = dir;
    return jar;
  }

  /// 登录前调用：把当前 jar 换成一个空的临时目录。
  ///
  /// 不这么做的话，新账号登录会写进上一个账号的 cookie 文件，
  /// 两个账号的票据混在一起，切换时会串号。
  Future<CookieJar> beginLogin() async {
    final Directory? pending = _pendingDir;
    if (pending == null) return jar;
    try {
      if (await pending.exists()) await pending.delete(recursive: true);
      await pending.create(recursive: true);
    } catch (_) {
      return jar;
    }
    jar = PersistCookieJar(ignoreExpires: false, storage: FileStorage(pending.path));
    dir = pending;
    return jar;
  }

  /// 登录成功：把临时目录整体改成 `<uid>`，并切换为当前会话。
  Future<CookieJar> commitLogin(String uid) async {
    final Directory? pending = _pendingDir;
    final Directory? target = _accountDir(uid);
    if (pending == null || target == null) return jar;
    try {
      if (await target.exists()) await target.delete(recursive: true);
      if (await pending.exists()) {
        await pending.rename(target.path);
      } else {
        await target.create(recursive: true);
      }
    } catch (_) {
      // 改名失败（被占用等）：退化为直接激活目标目录，至少还能用内存会话。
    }
    return activate(uid);
  }

  Future<void> cancelLogin() async {
    final Directory? pending = _pendingDir;
    if (pending == null) return;
    try {
      if (await pending.exists()) await pending.delete(recursive: true);
    } catch (_) {
      // 删不掉就留着，下次 beginLogin 会先清。
    }
    // 别把 jar 留在一个已删除的目录上：调用方可能还会读它（例如 hasSession）。
    jar = CookieJar();
    dir = null;
  }

  /// 旧版单文件会话升级：把 session 根目录下的 cookie 存储移进 `<uid>/`。
  ///
  /// 旧版用 FileStorage(根目录)，实际文件在 `<根>/ie0_ps1/` 子目录；
  /// 这里只迁移 `ie` 开头的存储目录与散文件，跳过 `.pending` 与账号目录。
  /// 返回 true 表示迁移成功（此后当前 jar 指向新目录）。
  Future<bool> promoteLegacy(String uid) async {
    final Directory? root = _root;
    final Directory? target = _accountDir(uid);
    if (root == null || target == null) return false;
    try {
      if (!await target.exists()) await target.create(recursive: true);
      await for (final FileSystemEntity entity in root.list()) {
        final String name = entity.path.split(Platform.pathSeparator).last;
        if (name == _kPendingDir || name == _kAccountsFile) continue;
        if (entity is Directory) {
          // 旧版存储目录固定以 ie 开头；其他目录是别的账号，别动。
          if (!name.startsWith('ie')) continue;
          final String dest = '${target.path}${Platform.pathSeparator}$name';
          final Directory destDir = Directory(dest);
          if (await destDir.exists()) await destDir.delete(recursive: true);
          await entity.rename(dest);
        } else if (entity is File) {
          await entity.rename('${target.path}${Platform.pathSeparator}$name');
        }
      }
      await activate(uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清掉某个账号的 cookie 文件，保留账号索引。
  Future<void> purgeAccount(String uid) async {
    final Directory? target = _accountDir(uid);
    if (target == null) return;
    // 当前 jar 正指向这个目录时，先清内存，再删文件。
    if (dir?.path == target.path) {
      try {
        await jar.deleteAll();
      } catch (_) {
        // 删不掉就等文件被移除。
      }
      jar = CookieJar();
      dir = null;
    }
    try {
      if (await target.exists()) await target.delete(recursive: true);
    } catch (_) {
      // 目录被占用时不强删。
    }
  }

  /// 清除所有账号的会话与索引（隐私页的「清除本机会话」）。
  Future<void> purgeAll() async {
    final Directory? root = _root;
    if (root == null) return;
    try {
      await jar.deleteAll();
    } catch (_) {
      // 忽略：下面会删目录。
    }
    jar = CookieJar();
    dir = null;
    try {
      await for (final FileSystemEntity entity in root.list()) {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else if (entity is File) {
          await entity.delete();
        }
      }
    } catch (_) {
      // 尽力而为。
    }
    final File? accounts = _accountsFile;
    try {
      if (accounts != null && await accounts.exists()) await accounts.delete();
    } catch (_) {
      // 同上。
    }
  }
}

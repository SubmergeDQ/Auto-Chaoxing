// 内存版会话存储：Widget 测试里不碰真实文件系统。
//
// testWidgets 运行在 FakeAsync 中，dart:io 的异步完成不会被推进，
// 直接用真实 SessionJar 会让用例卡在 bootstrap 的文件读取上。
import 'package:auto_chaoxing/platform/session_store.dart';
import 'package:cookie_jar/cookie_jar.dart';

class FakeSessionJar extends SessionJar {
  FakeSessionJar() : super(CookieJar(), null);

  final List<StoredAccount> _accounts = <StoredAccount>[];
  final Set<String> _uids = <String>{};

  @override
  bool get supported => true;

  @override
  bool get isAccountScoped => true;

  @override
  Future<List<StoredAccount>> loadAccounts() async => List<StoredAccount>.of(_accounts);

  @override
  Future<void> saveAccounts(List<StoredAccount> accounts) async {
    _accounts
      ..clear()
      ..addAll(accounts);
  }

  @override
  Future<bool> hasCookies(String uid) async => _uids.contains(uid);

  @override
  Future<CookieJar> activate(String uid) async {
    _uids.add(uid);
    jar = CookieJar();
    return jar;
  }

  @override
  Future<CookieJar> beginLogin() async {
    jar = CookieJar();
    dir = null;
    return jar;
  }

  @override
  Future<CookieJar> commitLogin(String uid) async {
    _uids.add(uid);
    return jar;
  }

  @override
  Future<void> cancelLogin() async {}

  @override
  Future<bool> promoteLegacy(String uid) async => false;

  @override
  Future<void> purgeAccount(String uid) async {
    _uids.remove(uid);
  }

  @override
  Future<void> purgeAll() async {
    _accounts.clear();
    _uids.clear();
  }
}

// 应用状态：账号、课程、章节、任务点与各自的加载态。
// 只做状态持有与编排，不拼 URL、不解析 HTML（那是 ChaoxingApi 的职责）。
// 通过构造参数注入 api，便于纯 Dart / Widget 测试替换成假实现。
import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/version.dart';

import '../core/chaoxing_api.dart';
import '../core/models.dart';
import '../platform/keep_alive_settings.dart';
import '../platform/session_store.dart';
import '../platform/window_shell.dart';
import '../platform/platform_services.dart';
import '../platform/run_keeper_android.dart';
import 'homework_controller.dart';
import 'keep_alive_probe.dart';
import 'run_controller.dart';
import 'sign_controller.dart';
import 'update_state.dart';

enum LoadState { idle, loading, ready, error }

class AppState extends ChangeNotifier {
  AppState({
    ChaoxingApi? api,
    Future<void> Function(Duration)? sleep,
    RunKeeper? runKeeper,
    this.session,
    UpdateState? update,
    KeepAliveSettings? keepAliveSettings,
    WindowShell? windowShell,
  })  : api = api ?? ChaoxingApi(),
        keepAliveSettings = keepAliveSettings ?? createKeepAliveSettings(),
        windowShell = windowShell ?? createWindowShell(),
        _sleep = sleep,
        runKeeper = runKeeper ?? createRunKeeper(),
        update = update ??
            UpdateState(currentVersion: kAppVersion, quitApp: quitApplication) {
    run = RunController(
      api: this.api,
      onChanged: _notify,
      sleep: _sleep,
      keeper: this.runKeeper,
    );
    probe = KeepAliveProbe(keeper: this.runKeeper);
    sign = SignController(
      api: this.api,
      onChanged: _notify,
      sleep: _sleep,
      keeper: this.runKeeper,
      // 监听与视频执行共用一个前台服务：执行中开始监听会互相覆盖通知，
      // 监听轮询也要在执行期间让路。
      isRunBusy: () => run.busy,
    );
    homework = HomeworkController(api: this.api, onChanged: _notify);

    // 安装更新前把后台任务停下来：执行中的章节、签到监听、前台服务都要收尾，
    // 否则安装器覆盖不了正在运行的 exe，或把一次执行打断在半路。
    this.update.prepareUpgrade = _prepareForUpgrade;
    // 自建的 UpdateState 用 WindowShell 真正退出（销毁窗口 + 结束进程）；
    // 测试注入的 UpdateState 保留它自己的 quitApp。
    if (update == null) this.update.quitApp = this.windowShell.quit;
  }

  /// 安装更新前的收尾：请求停止执行、停签到监听、结束前台服务。
  ///
  /// 最多等 2 秒让当前上报走完；超时也继续——更新不能因为一章没跑完就永远装不上。
  Future<void> _prepareForUpgrade() async {
    run.stop();
    sign.stopWatching();
    for (int i = 0; i < 20 && run.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await runKeeper.end();
  }

  final ChaoxingApi api;
  final Future<void> Function(Duration)? _sleep;

  /// 多账号会话存储。null 表示内存模式（测试或存储不可用），此时只能单账号。
  final SessionJar? session;

  /// 账号索引（uid / 名称 / 学校 / 上次使用时间）。按最近使用排序。
  List<StoredAccount> accounts = <StoredAccount>[];

  /// 当前生效的账号 uid。未登录时为 null。
  String? activeUid;

  /// 正在切换账号：期间禁止重复切换与开始执行。
  bool switchingAccount = false;

  bool get canSwitchAccounts => session?.supported ?? false;

  StoredAccount? get activeAccount {
    final String? uid = activeUid;
    if (uid == null) return null;
    for (final StoredAccount a in accounts) {
      if (a.uid == uid) return a;
    }
    return null;
  }

  /// 执行期间的后台保活。测试默认注入 Noop，真机是 Android 前台服务。
  final RunKeeper runKeeper;

  /// 保活设置页要读写的系统状态（通知权限、电池优化白名单）。
  final KeepAliveSettings keepAliveSettings;

  /// 桌面窗口与托盘。移动端是 Noop。
  final WindowShell windowShell;

  /// 后台保活自检。放在 AppState 而不是自检页里：自检要 3 分钟，
  /// 中途切去看课程再回来，结果不该消失——上一版把它挂在页面 State 上，一切页就清零。
  late final KeepAliveProbe probe;

  /// 执行会话：进度、日志与停止入口都在这里。
  late final RunController run;

  /// 签到：活动列表、手动签到与前台轮询。
  late final SignController sign;

  /// 作业：只读列表，提交在网页里完成。
  late final HomeworkController homework;

  /// 检查更新。放在 AppState：启动时的自动检查与关于页的手动检查要共用
  /// 同一个节流时间戳，否则「5 分钟只查一次」在两边各算各的。
  /// 可注入：widget 测试不该真的去打 GitHub。
  final UpdateState update;

  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    probe.dispose();
    update.dispose();
    run.dispose();
    sign.dispose();
    homework.dispose();
    unawaited(windowShell.dispose());
    runKeeper.dispose();
    super.dispose();
  }

  Profile? profile;

  /// 当前账号的头像。取不到时为 null，界面回退到首字。
  Uint8List? avatarBytes;

  /// 头像请求令牌：切换账号后旧请求回来不能覆盖新账号的头像。
  int _avatarToken = 0;

  bool get signedIn => profile != null;

  Future<void> _loadAvatar() async {
    final Profile? p = profile;
    final int token = ++_avatarToken;
    if (p == null) {
      avatarBytes = null;
      _notify();
      return;
    }
    final Result<Uint8List> r = await api.fetchAvatar(p.uid);
    if (_disposed || token != _avatarToken) return;
    avatarBytes = r is Ok<Uint8List> ? r.value : null;
    _notify();
  }

  /// 启动时正在校验本地会话。UI 据此显示「正在恢复登录」，
  /// 而不是先闪一下「未连接」再自己跳回来。
  bool restoringSession = false;

  /// 启动时用落盘的 cookie 恢复登录态。
  ///
  /// 没有 `_uid` 直接返回，不联网——没登录过的设备不该在开屏时打一次学习通。
  /// 校验失败（cookie 过期 / 被其他设备挤下线）静默回到未登录，不弹错误：
  /// 用户此刻只是想打开应用，不是想听一次失败通知。
  Future<void> bootstrap() async {
    await _loadRememberedUsername();
    // 自动检查更新不 await：开屏不该等 GitHub。内部有 5 分钟节流，
    // 连续开合应用不会反复打接口。
    unawaited(update.checkForUpdates());
    await _loadAccounts();

    // 优先恢复最近使用的账号：多账号下「上次在用哪个」比「根目录有没有 cookie」更有意义。
    final StoredAccount? recent = _mostRecentAccount();
    if (recent != null && await _hasSessionFor(recent.uid)) {
      final String? error = await switchAccount(recent.uid, silent: true);
      if (error == null) return;
    }
    await restoreSession();
  }

  Future<void> _loadAccounts() async {
    final SessionJar? store = session;
    if (store == null) return;
    accounts = await store.loadAccounts();
    _sortAccounts();
    _notify();
  }

  Future<bool> _hasSessionFor(String uid) async {
    final SessionJar? store = session;
    if (store == null) return false;
    return store.hasCookies(uid);
  }

  StoredAccount? _mostRecentAccount() {
    if (accounts.isEmpty) return null;
    return accounts.first;
  }

  StoredAccount? _findAccount(String uid) {
    for (final StoredAccount a in accounts) {
      if (a.uid == uid) return a;
    }
    return null;
  }

  void _sortAccounts() {
    accounts.sort((StoredAccount a, StoredAccount b) {
      final int ta = a.lastUsedAt?.millisecondsSinceEpoch ?? 0;
      final int tb = b.lastUsedAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
  }

  /// 登录成功后写入索引：同一 uid 覆盖旧记录，并把它挪到最前面。
  Future<void> _upsertAccount(Profile p, {String? username, bool touch = false}) async {
    final StoredAccount? old = _findAccount(p.uid);
    final StoredAccount next = StoredAccount(
      uid: p.uid,
      name: p.name,
      school: p.school,
      username: username ?? old?.username ?? '',
      lastUsedAt: touch ? DateTime.now() : old?.lastUsedAt,
    );
    accounts = <StoredAccount>[
      next,
      ...accounts.where((StoredAccount a) => a.uid != p.uid),
    ];
    _sortAccounts();
    await session?.saveAccounts(accounts);
    _notify();
  }

  Future<void> _touchAccount(String uid) async {
    final StoredAccount? old = _findAccount(uid);
    if (old == null) return;
    final StoredAccount next = old.copyWith(lastUsedAt: DateTime.now());
    accounts = <StoredAccount>[
      next,
      ...accounts.where((StoredAccount a) => a.uid != uid),
    ];
    _sortAccounts();
    await session?.saveAccounts(accounts);
    _notify();
  }

  /// 上次登录用过的手机号，用来预填登录框。
  ///
  /// 只记账号不记密码：手机号本身在设备上不算秘密，密码存盘没必要。
  String lastUsername = '';

  Future<void> _loadRememberedUsername() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kLastUsername);
      if (saved != null && saved.isNotEmpty) {
        lastUsername = saved;
        _notify();
      }
    } catch (_) {
      // 测试环境没有平台通道，读不到就当没记过。
    }
  }

  Future<void> _rememberUsername(String username) async {
    lastUsername = username;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastUsername, username);
    } catch (_) {
      // 记不住账号不影响登录本身。
    }
  }

  static const String _kLastUsername = 'last_username';

  Future<void> restoreSession() async {
    if (restoringSession || signedIn) return;
    if (!await api.hasSession()) return;
    restoringSession = true;
    _notify();
    try {
      final Result<Profile> r = await api.fetchProfile();
      if (r is Ok<Profile>) {
        profile = r.value;
        unawaited(_loadAvatar());
        // 旧版只有一个 session 根目录：校验通过后升级成按 uid 分目录。
        await _adoptLegacySession();
        _notify();
        await loadCourses();
      }
    } finally {
      restoringSession = false;
      _notify();
    }
  }

  /// 把旧版单会话迁移成多账号结构。失败不影响本次登录，只是下次仍走旧路径。
  Future<void> _adoptLegacySession() async {
    final SessionJar? store = session;
    final Profile? p = profile;
    if (store == null || p == null || !store.supported) return;
    if (store.isAccountScoped) return;
    final bool ok = await store.promoteLegacy(p.uid);
    if (!ok) return;
    api.useCookieJar(store.jar);
    activeUid = p.uid;
    await _upsertAccount(p, username: lastUsername, touch: true);
  }

  LoadState coursesState = LoadState.idle;
  List<Course> courses = <Course>[];
  String? coursesError;

  Course? selectedCourse;
  LoadState chaptersState = LoadState.idle;
  List<Chapter> chapters = <Chapter>[];
  String? chaptersError;

  final Map<String, List<TaskPoint>> _pointsCache = <String, List<TaskPoint>>{};
  final Map<String, String> _pointErrors = <String, String>{};
  final Set<String> _loadingChapters = <String>{};

  int get activeCourses => courses.where((Course c) => !c.archived).length;

  int get archivedCourses => courses.where((Course c) => c.archived).length;

  bool isChapterLoading(String chapterId) => _loadingChapters.contains(chapterId);

  List<TaskPoint>? pointsFor(String chapterId) => _pointsCache[chapterId];

  String? errorFor(String chapterId) => _pointErrors[chapterId];

  /// 返回 null 表示成功，否则返回可直接展示给用户的错误文案。
  ///
  /// 多账号下每次登录都先换到一个空会话目录：不这么做，新账号会把 cookie
  /// 写进上一个账号的存储，之后切换就串号了。失败时恢复原来的会话。
  Future<String?> signIn(String username, String password) async {
    // 登录新账号会清空当前账号的会话与执行状态，不能静默打断正在跑的章节。
    if (run.busy) return '正在执行章节，请先停止再登录新账号';

    final SessionJar? store = session;
    final bool usePending = store != null && store.supported;
    final CookieJar previous = api.cookieJar;
    if (usePending) {
      api.useCookieJar(await store.beginLogin());
    }

    final Result<Profile> r = await api.login(username.trim(), password);
    if (r is Err<Profile>) {
      if (usePending) {
        await store.cancelLogin();
        api.useCookieJar(previous);
      }
      return r.code == 'needsAttention'
          ? '${r.message}（需要人工验证，请先在浏览器完成一次登录）'
          : r.message;
    }

    final Profile p = (r as Ok<Profile>).value;
    if (usePending) {
      api.useCookieJar(await store.commitLogin(p.uid));
    }
    _resetAccountScopedState();
    profile = p;
    activeUid = p.uid;
    unawaited(_loadAvatar());
    unawaited(_rememberUsername(username.trim()));
    await _upsertAccount(p, username: username.trim(), touch: true);
    _notify();
    await loadCourses();
    return null;
  }

  /// 清掉与账号绑定的全部内存状态：切换/断开时不能让上一个账号的课程、执行、
  /// 签到与作业残留到新账号上。
  void _resetAccountScopedState() {
    run.reset();
    sign.reset();
    homework.reset();
    profile = null;
    avatarBytes = null;
    _avatarToken++;
    activeUid = null;
    courses = <Course>[];
    coursesState = LoadState.idle;
    coursesError = null;
    selectedCourse = null;
    chapters = <Chapter>[];
    chaptersState = LoadState.idle;
    chaptersError = null;
    _pointsCache.clear();
    _pointErrors.clear();
    _loadingChapters.clear();
    _notify();
  }

  /// 切换到另一个已保存的账号。
  ///
  /// 返回 null 表示成功。会话失效时返回原因，并把这个账号的失效文件清掉，
  /// 让用户走一次重新登录，而不是每次切换都失败。
  Future<String?> switchAccount(String uid, {bool silent = false}) async {
    if (switchingAccount) return '正在切换账号';
    if (run.busy) return '正在执行章节，请先停止再切换账号';
    final SessionJar? store = session;
    if (store == null || !store.supported) return '当前环境不支持切换账号';
    if (_findAccount(uid) == null) return '账号不存在';
    if (activeUid == uid && signedIn) return null;
    if (!await store.hasCookies(uid)) {
      return silent ? '该账号的会话文件不存在' : '这个账号的登录已失效，请重新登录';
    }

    switchingAccount = true;
    _notify();
    try {
      api.useCookieJar(await store.activate(uid));
      _resetAccountScopedState();
      final Result<Profile> r = await api.fetchProfile();
      if (r is Err<Profile>) {
        activeUid = uid;
        await store.purgeAccount(uid);
        api.useCookieJar(CookieJar());
        _notify();
        final String reason = r.code == 'authExpired' ? '会话已过期，请重新登录这个账号' : r.message;
        return silent ? reason : reason;
      }
      profile = (r as Ok<Profile>).value;
      activeUid = uid;
      unawaited(_loadAvatar());
      await _touchAccount(uid);
      _notify();
      await loadCourses();
      return null;
    } finally {
      switchingAccount = false;
      _notify();
    }
  }

  /// 断开当前账号：删掉它的 cookie 文件，但保留账号记录，方便下次快速重登。
  Future<void> signOut() async {
    final String? uid = activeUid ?? profile?.uid;
    _resetAccountScopedState();
    final SessionJar? store = session;
    if (store != null && store.supported && uid != null) {
      await store.purgeAccount(uid);
      api.useCookieJar(CookieJar());
    } else {
      await api.clearSession();
    }
    _notify();
  }

  /// 从账号列表里彻底移除一个账号（会话文件 + 索引记录）。
  Future<void> removeAccount(String uid) async {
    final bool current = uid == activeUid || uid == profile?.uid;
    if (current) _resetAccountScopedState();
    final SessionJar? store = session;
    if (store != null && store.supported) {
      await store.purgeAccount(uid);
      if (current) api.useCookieJar(CookieJar());
    }
    accounts = accounts.where((StoredAccount a) => a.uid != uid).toList();
    await store?.saveAccounts(accounts);
    _notify();
  }

  /// 清除本机全部账号与会话（隐私页）。
  Future<void> signOutAll() async {
    _resetAccountScopedState();
    accounts = <StoredAccount>[];
    final SessionJar? store = session;
    if (store != null && store.supported) {
      await store.purgeAll();
    } else {
      await api.clearSession();
    }
    api.useCookieJar(CookieJar());
    _notify();
  }

  Future<void> loadCourses() async {
    coursesState = LoadState.loading;
    coursesError = null;
    _notify();
    final Result<List<Course>> r = await api.fetchCourses();
    if (r is Err<List<Course>>) {
      courses = <Course>[];
      coursesError = r.message;
      coursesState = LoadState.error;
    } else {
      courses = (r as Ok<List<Course>>).value;
      coursesState = LoadState.ready;
    }
    _notify();
  }

  Future<void> selectCourse(Course course) async {
    selectedCourse = course;
    chaptersState = LoadState.loading;
    chaptersError = null;
    chapters = <Chapter>[];
    _pointsCache.clear();
    _pointErrors.clear();
    _notify();

    final Result<List<Chapter>> r = await api.fetchChapters(
      courseId: course.courseId,
      classId: course.classId,
      cpi: course.cpi,
    );
    if (r is Err<List<Chapter>>) {
      chaptersError = r.message;
      chaptersState = LoadState.error;
    } else {
      chapters = (r as Ok<List<Chapter>>).value;
      chaptersState = LoadState.ready;
    }
    _notify();
  }

  /// 展开章节时按需拉任务点；已缓存或正在加载的章节不重复请求。
  Future<void> loadPoints(Chapter chapter) async {
    final Course? course = selectedCourse;
    if (course == null ||
        _pointsCache.containsKey(chapter.chapterId) ||
        _loadingChapters.contains(chapter.chapterId)) {
      return;
    }
    _loadingChapters.add(chapter.chapterId);
    _notify();

    final Result<ChapterCards> r = await api.fetchCards(
      courseId: course.courseId,
      classId: course.classId,
      chapterId: chapter.chapterId,
      cpi: course.cpi,
    );
    _loadingChapters.remove(chapter.chapterId);
    if (r is Err<ChapterCards>) {
      _pointErrors[chapter.chapterId] = r.code == 'locked'
          ? '章节未开放：上一章未完成或测验未提交'
          : r.message;
      _pointsCache[chapter.chapterId] = <TaskPoint>[];
    } else {
      _pointsCache[chapter.chapterId] = (r as Ok<ChapterCards>).value.points;
      _pointErrors.remove(chapter.chapterId);
    }
    _notify();
  }

  void clearSelection() {
    selectedCourse = null;
    chapters = <Chapter>[];
    chaptersState = LoadState.idle;
    chaptersError = null;
    _pointsCache.clear();
    _pointErrors.clear();
    _notify();
  }
}

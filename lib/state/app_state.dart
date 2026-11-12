// 应用状态：账号、课程、章节、任务点与各自的加载态。
// 只做状态持有与编排，不拼 URL、不解析 HTML（那是 ChaoxingApi 的职责）。
// 通过构造参数注入 api，便于纯 Dart / Widget 测试替换成假实现。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/version.dart';

import '../core/chaoxing_api.dart';
import '../core/models.dart';
import '../platform/platform_services.dart';
import '../platform/run_keeper_android.dart';
import 'keep_alive_probe.dart';
import 'run_controller.dart';
import 'update_state.dart';

enum LoadState { idle, loading, ready, error }

class AppState extends ChangeNotifier {
  AppState({
    ChaoxingApi? api,
    Future<void> Function(Duration)? sleep,
    RunKeeper? runKeeper,
    Future<void> Function()? purgeSession,
    UpdateState? update,
  })  : api = api ?? ChaoxingApi(),
        _sleep = sleep,
        runKeeper = runKeeper ?? createRunKeeper(),
        _purgeSession = purgeSession,
        update = update ??
            UpdateState(currentVersion: kAppVersion, quitApp: quitApplication) {
    run = RunController(
      api: this.api,
      onChanged: _notify,
      sleep: _sleep,
      keeper: this.runKeeper,
    );
    probe = KeepAliveProbe(keeper: this.runKeeper);
  }

  final ChaoxingApi api;
  final Future<void> Function(Duration)? _sleep;

  /// 断开连接时抹掉落盘的会话（cookie 文件）。
  /// 由 main 注入 SessionJar.purge；测试里为 null，此时只清内存 cookie。
  final Future<void> Function()? _purgeSession;

  /// 执行期间的后台保活。测试默认注入 Noop，真机是 Android 前台服务。
  final RunKeeper runKeeper;

  /// 后台保活自检。放在 AppState 而不是自检页里：自检要 3 分钟，
  /// 中途切去看课程再回来，结果不该消失——上一版把它挂在页面 State 上，一切页就清零。
  late final KeepAliveProbe probe;

  /// 执行会话：进度、日志与停止入口都在这里。
  late final RunController run;

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
    runKeeper.dispose();
    super.dispose();
  }

  Profile? profile;

  bool get signedIn => profile != null;

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
    await restoreSession();
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
        _notify();
        await loadCourses();
      }
    } finally {
      restoringSession = false;
      _notify();
    }
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
  Future<String?> signIn(String username, String password) async {
    final Result<Profile> r = await api.login(username.trim(), password);
    if (r is Err<Profile>) {
      return r.code == 'needsAttention'
          ? '${r.message}（需要人工验证，请先在浏览器完成一次登录）'
          : r.message;
    }
    profile = (r as Ok<Profile>).value;
    _notify();
    unawaited(_rememberUsername(username.trim()));
    await loadCourses();
    return null;
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

  /// 断开连接：内存状态先清空（界面立刻回到未登录），再抹掉落盘会话。
  ///
  /// 顺序不能反：等文件删完再刷新界面的话，弱网或文件被占用时
  /// 用户会看到一个「点了没反应」的按钮。
  Future<void> signOut() async {
    run.reset();
    profile = null;
    courses = <Course>[];
    coursesState = LoadState.idle;
    coursesError = null;
    clearSelection();
    _notify();
    await api.clearSession();
    final Future<void> Function()? purge = _purgeSession;
    if (purge != null) await purge();
  }
}

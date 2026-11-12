// 应用状态：账号、课程、章节、任务点与各自的加载态。
// 只做状态持有与编排，不拼 URL、不解析 HTML（那是 ChaoxingApi 的职责）。
// 通过构造参数注入 api，便于纯 Dart / Widget 测试替换成假实现。
import 'package:flutter/foundation.dart';

import '../core/chaoxing_api.dart';
import '../core/models.dart';
import 'run_controller.dart';

enum LoadState { idle, loading, ready, error }

class AppState extends ChangeNotifier {
  AppState({ChaoxingApi? api, Future<void> Function(Duration)? sleep})
      : api = api ?? ChaoxingApi(),
        _sleep = sleep {
    run = RunController(api: this.api, onChanged: _notify, sleep: _sleep);
  }

  final ChaoxingApi api;
  final Future<void> Function(Duration)? _sleep;

  /// 执行会话：进度、日志与停止入口都在这里。
  late final RunController run;

  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    run.dispose();
    super.dispose();
  }

  Profile? profile;

  bool get signedIn => profile != null;

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

  void signOut() {
    run.reset();
    profile = null;
    courses = <Course>[];
    coursesState = LoadState.idle;
    coursesError = null;
    clearSelection();
  }
}

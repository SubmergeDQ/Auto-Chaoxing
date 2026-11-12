// 应用状态：账号、课程、章节、任务点与各自的加载态。
// 只做状态持有与编排，不拼 URL、不解析 HTML（那是 ChaoxingApi 的职责）。
// 通过构造参数注入 api，便于纯 Dart / Widget 测试替换成假实现。
import 'package:flutter/foundation.dart';

import '../core/chaoxing_api.dart';
import '../core/models.dart';

enum LoadState { idle, loading, ready, error }

class AppState extends ChangeNotifier {
  AppState({ChaoxingApi? api}) : api = api ?? ChaoxingApi();

  final ChaoxingApi api;

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
    notifyListeners();
    await loadCourses();
    return null;
  }

  Future<void> loadCourses() async {
    coursesState = LoadState.loading;
    coursesError = null;
    notifyListeners();
    final Result<List<Course>> r = await api.fetchCourses();
    if (r is Err<List<Course>>) {
      courses = <Course>[];
      coursesError = r.message;
      coursesState = LoadState.error;
    } else {
      courses = (r as Ok<List<Course>>).value;
      coursesState = LoadState.ready;
    }
    notifyListeners();
  }

  Future<void> selectCourse(Course course) async {
    selectedCourse = course;
    chaptersState = LoadState.loading;
    chaptersError = null;
    chapters = <Chapter>[];
    _pointsCache.clear();
    _pointErrors.clear();
    notifyListeners();

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
    notifyListeners();
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
    notifyListeners();

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
    notifyListeners();
  }

  void clearSelection() {
    selectedCourse = null;
    chapters = <Chapter>[];
    chaptersState = LoadState.idle;
    chaptersError = null;
    _pointsCache.clear();
    _pointErrors.clear();
    notifyListeners();
  }

  void signOut() {
    profile = null;
    courses = <Course>[];
    coursesState = LoadState.idle;
    coursesError = null;
    clearSelection();
  }
}

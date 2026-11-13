// 作业列表会话：只读列表，刷新与错误状态。
//
// 不做提交：作答页的隐藏字段集合未实测确认，猜字段提交会出现
// 「本地以为交了、平台没收到」——比不提供提交更糟。
import 'dart:async';

import '../core/chaoxing_api.dart';
import '../core/models.dart';

class HomeworkController {
  HomeworkController({
    required ChaoxingApi api,
    required void Function() onChanged,
  })  : _api = api,
        _onChanged = onChanged;

  final ChaoxingApi _api;
  final void Function() _onChanged;

  Course? course;
  List<HomeworkItem> items = <HomeworkItem>[];
  bool loading = false;
  String? error;

  bool _disposed = false;

  Future<void> open(Course value) async {
    if (_disposed) return;
    if (course?.key != value.key) {
      course = value;
      items = <HomeworkItem>[];
      error = null;
      _onChanged();
    }
    await refresh();
  }

  Future<void> refresh() async {
    final Course? current = course;
    if (current == null || _disposed) return;
    loading = true;
    error = null;
    _onChanged();

    final Result<List<HomeworkItem>> r = await _api.fetchHomeworks(course: current);
    if (_disposed) return;
    loading = false;
    if (r is Err<List<HomeworkItem>>) {
      error = r.code == 'authExpired' ? '登录已失效，请重新连接账号' : r.message;
    } else {
      items = (r as Ok<List<HomeworkItem>>).value;
    }
    _onChanged();
  }

  void reset() {
    course = null;
    items = <HomeworkItem>[];
    loading = false;
    error = null;
    _onChanged();
  }

  void dispose() {
    _disposed = true;
  }
}

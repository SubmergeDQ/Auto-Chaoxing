// 保活的测试替身：只记录调用，不碰任何原生通道。
import 'dart:async';

import 'package:auto_chaoxing/platform/platform_services.dart';

class RunKeeperStub implements RunKeeper {
  RunKeeperStub({this.beginResult = true});

  /// begin 的返回值。false 用来模拟「拿不到通知权限 / 服务起不来」。
  bool beginResult;

  int beginCalls = 0;
  int updateCalls = 0;
  int finishCalls = 0;
  int endCalls = 0;

  String beginTitle = '';
  String beginBody = '';

  /// 每次推给通知的正文，按顺序记下来，用于断言「文案确实在跟着进度走」。
  final List<String> notices = <String>[];

  String? finishedTitle;
  String? finishedBody;

  final StreamController<void> _stops = StreamController<void>.broadcast();

  @override
  bool get supported => true;

  @override
  Stream<void> get stopRequests => _stops.stream;

  /// 模拟用户在系统通知上点「停止」。
  void tapStopOnNotification() => _stops.add(null);

  @override
  Future<bool> ensureNotificationPermission() async => beginResult;

  @override
  Future<bool> begin({required String title, required String body}) async {
    beginCalls++;
    beginTitle = title;
    beginBody = body;
    notices.add(body);
    return beginResult;
  }

  @override
  Future<void> update({required String title, required String body}) async {
    updateCalls++;
    notices.add(body);
  }

  @override
  Future<void> finish({required String title, required String body}) async {
    finishCalls++;
    finishedTitle = title;
    finishedBody = body;
  }

  @override
  Future<void> end() async {
    endCalls++;
  }

  @override
  void dispose() {
    _stops.close();
  }
}

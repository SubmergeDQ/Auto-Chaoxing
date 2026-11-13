// 可注入的协议假实现：只返回预设数据，不发任何网络请求。
// 供状态测试、Widget 测试与视觉取证共用，保证截图里的状态是确定的。
import 'dart:async';
import 'dart:typed_data';

import 'package:auto_chaoxing/core/chaoxing_api.dart';
import 'package:auto_chaoxing/core/models.dart';
import 'package:cookie_jar/cookie_jar.dart';

/// 1x1 透明 PNG：头像用例只需要「是一张能解码的图」。
final Uint8List kTinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeChaoxingApi extends ChaoxingApi {
  FakeChaoxingApi({
    Profile? profile,
    this.courses = const <Course>[],
    this.chapters = const <Chapter>[],
    this.points = const <TaskPoint>[],
    this.loginError,
    this.loginErrorCode = 'api',
    this.coursesError,
    this.chaptersError,
    this.cardsErrorCode,
    this.signActivities = const <SignActivity>[],
    this.homeworks = const <HomeworkItem>[],
  }) : demoProfile = profile ??
            const Profile(
              uid: '10086',
              name: '林知远',
              fid: '666',
              school: '示例大学',
            );

  final Profile demoProfile;
  List<Course> courses;
  List<Chapter> chapters;
  List<TaskPoint> points;
  String? loginError;
  String loginErrorCode;
  String? coursesError;
  String? chaptersError;
  String? cardsErrorCode;

  /// 按章节指定任务点；没配的章节沿用 [points]。
  /// 整门课批量执行的测试靠它造出「有的章有视频、有的章没有」。
  final Map<String, List<TaskPoint>> pointsByChapter = <String, List<TaskPoint>>{};

  /// 视频总时长（秒）。默认 120，按 60 秒步长每个任务点上报 3 次。
  int videoSeconds = 120;

  /// 这些 objectId 对应的任务点永远判为未通过，用来覆盖失败分支。
  final Set<String> neverPass = <String>{};

  /// 登录返回的资料；多账号测试里切到第二个账号前改它。
  Profile? loginProfile;

  /// 按 uid 返回资料，用于验证「切换账号后拿到的是那个账号的信息」。
  final Map<String, Profile> profilesByUid = <String, Profile>{};

  /// 头像数据；null 表示取不到（界面应回退到首字）。
  Uint8List? avatarData;
  int avatarCalls = 0;

  /// 设置后，第一次上报会挂起，测试可在运行中调用停止。
  Completer<void>? reportGate;

  /// 设为 true 时所有上报都返回登录失效；设为 >=0 时在 N 次上报后失效。
  bool authExpiredOnReport = false;
  int authExpiredAfterReports = -1;

  int loginCalls = 0;
  int coursesCalls = 0;
  int chaptersCalls = 0;
  int cardsCalls = 0;
  int reportCalls = 0;
  int statusCalls = 0;
  int signActivitiesCalls = 0;
  int signCalls = 0;

  /// 签到活动列表；按需在用例里替换。
  List<SignActivity> signActivities = const <SignActivity>[];

  /// 设置后 activelist 返回错误，用来覆盖签到页的错误态。
  String? signActivitiesError;

  /// 每次签到返回的结果，默认成功。改成 needFace 等可覆盖提示分支。
  SignAttempt signAttempt = const SignAttempt(SignOutcome.success, message: '签到成功');

  /// 已成功发起过的签到，用来断言幂等没有重复提交。
  final List<String> signedActiveIds = <String>[];

  /// 作业列表与错误。
  List<HomeworkItem> homeworks = const <HomeworkItem>[];
  String? homeworksError;
  int homeworksCalls = 0;

  /// 每次上报的 playingTime，按调用顺序记录，用来断言续跑起点。
  final List<int> reportedTimes = <int>[];

  @override
  Future<Result<Profile>> login(String username, String password) async {
    loginCalls++;
    if (loginError != null) return Err<Profile>(loginErrorCode, loginError!);
    final Profile p = loginProfile ?? demoProfile;
    // 真实登录会下发 `_uid`；多账号切换靠它认出当前是哪个账号。
    try {
      await cookieJar.saveFromResponse(
        Uri.parse('https://chaoxing.com'),
        <Cookie>[Cookie('_uid', p.uid)..domain = '.chaoxing.com'..path = '/'],
      );
    } catch (_) {
      // 内存模式没有落盘能力，忽略。
    }
    profile = p;
    return Ok<Profile>(p);
  }

  @override
  Future<Result<Profile>> fetchProfile() async {
    try {
      final List<Cookie> cookies =
          await cookieJar.loadForRequest(Uri.parse('https://chaoxing.com'));
      for (final Cookie c in cookies) {
        if (c.name != '_uid') continue;
        final Profile? p = profilesByUid[c.value];
        if (p != null) {
          profile = p;
          return Ok<Profile>(p);
        }
      }
    } catch (_) {
      // 读不到就按默认账号处理。
    }
    profile = demoProfile;
    return Ok<Profile>(demoProfile);
  }

  @override
  Future<Result<Uint8List>> fetchAvatar(String uid) async {
    avatarCalls++;
    final Uint8List? data = avatarData;
    if (data == null) return const Err<Uint8List>('avatar', '没有取到头像');
    return Ok<Uint8List>(data);
  }

  @override
  Future<Result<List<Course>>> fetchCourses() async {
    coursesCalls++;
    if (coursesError != null) return Err<List<Course>>('network', coursesError!);
    return Ok<List<Course>>(courses);
  }

  @override
  Future<Result<List<Chapter>>> fetchChapters({
    required String courseId,
    required String classId,
    String cpi = '',
  }) async {
    chaptersCalls++;
    if (chaptersError != null) return Err<List<Chapter>>('network', chaptersError!);
    return Ok<List<Chapter>>(chapters);
  }

  @override
  Future<Result<ChapterCards>> fetchCards({
    required String courseId,
    required String classId,
    required String chapterId,
    String cpi = '',
    int page = 0,
  }) async {
    cardsCalls++;
    if (cardsErrorCode == 'locked') {
      // 与真实 API 的 locked 文案保持一致，避免假实现给出与线上不同的提示。
      return const Err<ChapterCards>('locked', '章节未开放：上一章未完成或测验未提交');
    }
    if (cardsErrorCode != null) {
      return Err<ChapterCards>(cardsErrorCode!, '卡片读取失败');
    }
    return Ok<ChapterCards>(
      ChapterCards(
        reportUrl: 'https://mooc1.chaoxing.com/multimedia/log',
        fid: '666',
        userId: demoProfile.uid,
        points: pointsByChapter[chapterId] ?? points,
      ),
    );
  }

  @override
  Future<Result<List<SignActivity>>> fetchSignActivities({
    required Course course,
  }) async {
    signActivitiesCalls++;
    final String? error = signActivitiesError;
    if (error != null) return Err<List<SignActivity>>('network', error);
    return Ok<List<SignActivity>>(signActivities);
  }

  @override
  Future<Result<SignAttempt>> signIn({
    required Course course,
    required SignActivity activity,
    required String uid,
    required String name,
    required String fid,
  }) async {
    signCalls++;
    if (signAttempt.ok) signedActiveIds.add(activity.activeId);
    return Ok<SignAttempt>(signAttempt);
  }

  @override
  Future<Result<List<HomeworkItem>>> fetchHomeworks({
    required Course course,
  }) async {
    homeworksCalls++;
    final String? error = homeworksError;
    if (error != null) return Err<List<HomeworkItem>>('network', error);
    return Ok<List<HomeworkItem>>(homeworks);
  }

  @override
  Future<Result<VideoStatus>> videoStatus(String objectId, String fid) async {
    statusCalls++;
    if (videoSeconds <= 0) return const Err<VideoStatus>('api', '视频时长异常');
    return Ok<VideoStatus>(
      VideoStatus(objectId: objectId, duration: videoSeconds, dtoken: 'dt-$objectId'),
    );
  }

  @override
  Future<Result<bool>> reportProgress({
    required String reportUrl,
    required String dtoken,
    required TaskPoint point,
    required String classId,
    required String uid,
    required int playTime,
    required int duration,
  }) async {
    reportCalls++;
    reportedTimes.add(playTime);
    final Completer<void>? gate = reportGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    if (authExpiredOnReport ||
        (authExpiredAfterReports >= 0 && reportCalls > authExpiredAfterReports)) {
      return const Err<bool>('authExpired', '登录已失效');
    }
    if (neverPass.contains(point.objectId)) return const Ok<bool>(false);
    return Ok<bool>(playTime >= duration);
  }
}

const List<Course> kDemoCourses = <Course>[
  Course(
    courseId: '2410001',
    classId: '88001',
    cpi: '126843',
    name: '高等数学（上）',
    teacher: '李文博',
  ),
  Course(
    courseId: '2410002',
    classId: '88002',
    cpi: '126844',
    name: '设计与思维',
    teacher: '周敏',
  ),
  Course(
    courseId: '2410003',
    classId: '88003',
    cpi: '126845',
    name: '空间光环境基础',
    teacher: '陈昱',
  ),
  Course(
    courseId: '2410004',
    classId: '88004',
    cpi: '126846',
    name: '大学英语（二）',
    teacher: '王琳',
    archived: true,
  ),
];

const List<Chapter> kDemoChapters = <Chapter>[
  Chapter(chapterId: '510001', title: '第一章 函数与极限'),
  Chapter(chapterId: '510002', title: '第二章 导数与微分'),
  Chapter(chapterId: '510003', title: '第三章 微分中值定理'),
  Chapter(chapterId: '510004', title: '第四章 不定积分'),
];

const List<TaskPoint> kDemoPoints = <TaskPoint>[
  TaskPoint(type: 'video', jobId: 'j-101', name: '1.1 映射与函数', objectId: 'o-101'),
  TaskPoint(type: 'document', jobId: 'j-102', name: '第一章课程讲义.pdf'),
  TaskPoint(type: 'video', jobId: 'j-103', name: '1.2 数列的极限', objectId: 'o-103'),
  TaskPoint(type: 'workid', jobId: 'j-104', name: '第一章章节作业'),
];

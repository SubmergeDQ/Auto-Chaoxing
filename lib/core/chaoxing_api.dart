// 学习通 HTTP 客户端：只负责请求、Cookie、解析与错误归一。
// 不包含重试策略与业务循环（那是 task_runner 的事）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'crypto.dart';
import 'homework_rules.dart';
import 'models.dart';
import 'sign_rules.dart';

/// gas 接口按 UA 放行：缺少 `com.chaoxing.mobile/ChaoXingStudy…` 这一段会直接 403，
/// 普通 Chrome 移动端 UA 也不例外。其余字段保持真实机型，避免风控把会话判成异常设备。
const String kMobileUa =
    'Mozilla/5.0 (Linux; Android 11; MI10 Build/QKQ1.190929.002; wv) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/79.0.3945.116 '
    'Mobile Safari/537.36 (device:MI10) Language/zh_CN '
    'com.chaoxing.mobile/ChaoXingStudy_3_6.7.5_android_phone_10941_314';

/// 登录失效的判定特征串。响应是 HTML 时先过一遍这个，再谈解析。
const List<String> _authExpiredMarkers = <String>[
  'passport2.chaoxing.com/login',
  'id="loginForm"',
  'id="phone-mobile"',
];

class ChaoxingApi {
  ChaoxingApi({CookieJar? cookieJar})
      : cookieJar = cookieJar ?? CookieJar(),
        _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 25),
            followRedirects: true,
            validateStatus: (int? s) => s != null && s < 500,
            headers: <String, dynamic>{
              'User-Agent': kMobileUa,
              'Accept': '*/*',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'X-Requested-With': 'com.chaoxing.mobile',
            },
          ),
        ) {
    // 这里必须用字段而不是构造参数：参数是 CookieJar?，字段已保证非空。
    _installCookieManager();
  }

  /// 当前 CookieJar。切换账号时用 [useCookieJar] 整体替换。
  CookieJar cookieJar;
  final Dio _dio;
  CookieManager? _cookieManager;

  void _installCookieManager() {
    final CookieManager? old = _cookieManager;
    if (old != null) _dio.interceptors.remove(old);
    _cookieManager = CookieManager(cookieJar);
    _dio.interceptors.add(_cookieManager!);
  }

  /// 热切换 CookieJar：多账号切换时不需要重建 API 与全部控制器。
  void useCookieJar(CookieJar jar) {
    cookieJar = jar;
    _installCookieManager();
  }

  Profile? profile;

  /// 本地是否还有登录票据（不联网）。
  ///
  /// `_uid` 是学习通登录成功后一定会下发的 cookie，用它判断「值不值得再验一次」：
  /// 没有就说明这台设备从没登录过或已主动断开，直接跳过启动时的联网校验。
  Future<bool> hasSession() async {
    try {
      final List<Cookie> cs =
          await cookieJar.loadForRequest(Uri.parse('https://chaoxing.com'));
      return cs.any((Cookie c) => c.name == '_uid' && c.value.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// 退出登录：清掉全部 cookie。落盘清理由调用方（SessionJar）负责。
  Future<void> clearSession() async {
    profile = null;
    try {
      await cookieJar.deleteAll();
    } catch (_) {
      // 清不掉就等过期，不影响当前会话。
    }
  }

  /// 登录：账号密码先本地 AES-CBC 加密，再提交。
  Future<Result<Profile>> login(String username, String password) async {
    try {
      // 先取一次登录页：passport 会下发 JSESSIONID / route，
      // 直接 POST 到 fanyalogin 在部分线路会被判成非法请求。
      try {
        await _dio.get<String>(
          'https://passport2.chaoxing.com/login',
          queryParameters: <String, dynamic>{'fid': '', 'refer': 'https://i.chaoxing.com'},
        );
      } on DioException {
        // 预请求失败不致命：POST 带上 Origin/Referer 通常也能过。
      }
      final Response<String> resp = await _dio.post<String>(
        'https://passport2.chaoxing.com/fanyalogin',
        data: <String, dynamic>{
          'fid': '-1',
          'refer': 'https://i.chaoxing.com',
          't': 'true',
          'forbidotherlogin': '0',
          'validate': '',
          'uname': aesCbcBase64(username.trim()),
          'password': aesCbcBase64(password),
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, dynamic>{
            'Origin': 'https://passport2.chaoxing.com',
            'Referer':
                'https://passport2.chaoxing.com/login?fid=&refer=https%3A%2F%2Fi.chaoxing.com',
          },
        ),
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null) {
        return const Err<Profile>('parse', '登录响应无法解析');
      }
      if (json['status'] == true) {
        final Result<Profile> me = await fetchProfile();
        return me;
      }
      final String msg = '${json['msg2'] ?? json['mes'] ?? json['msg'] ?? '登录失败'}';
      if (json['needVcode'] == true ||
          json['containTwoFactorLogin'] == true ||
          json['weakpwd'] == true ||
          json['passwordTimeout'] == true) {
        return Err<Profile>('needsAttention', msg.isEmpty ? '需要验证码或二次验证' : msg);
      }
      return Err<Profile>('api', msg);
    } on DioException catch (e) {
      return Err<Profile>('network', _netMessage(e));
    }
  }

  Future<Result<Profile>> fetchProfile() async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://sso.chaoxing.com/apis/login/userLogin4Uname.do',
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null || json['result'] != 1) {
        return const Err<Profile>('authExpired', '登录已失效');
      }
      final Map<String, dynamic> msg = (json['msg'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final Profile p = Profile.fromJson(msg);
      if (p.uid.isEmpty) {
        return const Err<Profile>('authExpired', '未取到账号信息');
      }
      profile = p;
      return Ok<Profile>(p);
    } on DioException catch (e) {
      return Err<Profile>('network', _netMessage(e));
    }
  }

  /// 学习通头像。按 uid 取，失败由调用方回退到首字/图标。
  Future<Result<Uint8List>> fetchAvatar(String uid) async {
    if (uid.isEmpty) return const Err<Uint8List>('parse', '缺少账号 id');
    // 常见尺寸后缀：先试 120，再退回原图。
    for (final String url in <String>[
      'https://photo.chaoxing.com/p/${uid}_120',
      'https://photo.chaoxing.com/p/$uid',
    ]) {
      try {
        final Response<List<int>> resp = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final List<int>? bytes = resp.data;
        if (resp.statusCode != 200 || bytes == null || bytes.isEmpty) continue;
        if (!_looksLikeImage(bytes)) continue;
        return Ok<Uint8List>(Uint8List.fromList(bytes));
      } on DioException {
        // 换下一个候选。
      }
    }
    return const Err<Uint8List>('avatar', '没有取到头像');
  }

  /// 头像接口失败时会回 HTML 或空内容，按文件头判断比看状态码可靠。
  static bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final bool jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    final bool png = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final bool gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    final bool webp = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
    return jpeg || png || gif || webp;
  }

  Future<Result<List<Course>>> fetchCourses() async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
        queryParameters: <String, dynamic>{'view': 'json', 'rss': '1'},
      );
      final String body = resp.data ?? '';
      if (_looksLikeLogin(body)) {
        return const Err<List<Course>>('authExpired', '登录已失效');
      }
      final Map<String, dynamic>? json = _tryJson(body);
      if (json == null) return const Err<List<Course>>('parse', '课程列表无法解析');
      final List<Course> out = <Course>[];
      final List<dynamic> channels =
          (json['channelList'] ?? json['channel'] ?? <dynamic>[]) as List<dynamic>;
      for (final dynamic ch in channels) {
        final Map<String, dynamic> channel = (ch as Map).cast<String, dynamic>();
        final Map<String, dynamic> content =
            (channel['content'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final Map<String, dynamic> courseWrap =
            (content['course'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final List<dynamic> data = (courseWrap['data'] ?? <dynamic>[]) as List<dynamic>;
        if (data.isEmpty) continue;
        final Map<String, dynamic> c = (data.first as Map).cast<String, dynamic>();
        final String courseId = '${c['id'] ?? ''}';
        final String classId = '${content['id'] ?? ''}';
        if (!_isDigits(courseId) || !_isDigits(classId)) continue;
        out.add(
          Course(
            courseId: courseId,
            classId: classId,
            cpi: '${content['cpi'] ?? channel['cpi'] ?? ''}',
            name: '${c['name'] ?? '未命名课程'}',
            teacher: '${c['teacherfactor'] ?? ''}',
            archived: content['isFiled'] == 1 || content['isretire'] == 1,
          ),
        );
      }
      return Ok<List<Course>>(out);
    } on DioException catch (e) {
      return Err<List<Course>>('network', _netMessage(e));
    }
  }

  /// 章节树：移动端 gas 接口返回课程的知识节点。
  ///
  /// 旧的 `mycourse/studentcourse` 页面现在会 302 到登录跳板，已不能取章节。
  /// gas 接口要求 `personid` 传课程列表里的 cpi，并把 classId 放在 `id`。
  Future<Result<List<Chapter>>> fetchChapters({
    required String courseId,
    required String classId,
    String cpi = '',
  }) async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1-api.chaoxing.com/gas/clazz',
        queryParameters: <String, dynamic>{
          'id': classId,
          'personid': cpi,
          'fields': _chapterFields,
          'view': 'json',
        },
        options: Options(
          headers: <String, dynamic>{'Referer': 'http://i.mooc.chaoxing.com'},
        ),
      );
      final String body = resp.data ?? '';
      if (_looksLikeLogin(body)) {
        return const Err<List<Chapter>>('authExpired', '登录已失效');
      }
      final Map<String, dynamic>? json = _tryJson(body);
      if (json == null) {
        return Err<List<Chapter>>(
          'parse',
          resp.statusCode == 200 ? '章节列表无法解析' : '章节接口返回异常（${resp.statusCode}）',
        );
      }
      final List<Map<String, dynamic>> nodes = _chapterNodes(json);
      if (nodes.isEmpty) {
        return const Err<List<Chapter>>('parse', '章节列表为空');
      }
      // 顶层章通常只是分组，任务点挂在子节点上；只保留叶子节点，
      // 没有子节点的顶层章本身就是可执行节点，也要保留。
      final Set<String> parents = <String>{};
      for (final Map<String, dynamic> n in nodes) {
        final String pid = '${n['parentnodeid'] ?? ''}';
        if (pid.isNotEmpty && pid != '0') parents.add(pid);
      }
      final List<Map<String, dynamic>> leaves = nodes
          .where((Map<String, dynamic> n) => !parents.contains('${n['id'] ?? ''}'))
          .toList()
        ..sort(_compareChapterNode);
      final List<Chapter> out = <Chapter>[];
      for (final Map<String, dynamic> n in leaves) {
        final String id = '${n['id'] ?? ''}';
        if (!_isDigits(id)) continue;
        out.add(Chapter(chapterId: id, title: _chapterTitle(n)));
      }
      return Ok<List<Chapter>>(out);
    } on DioException catch (e) {
      return Err<List<Chapter>>('network', _netMessage(e));
    }
  }

  /// 章节卡片。返回 locked 表示章节未开放（上一章未完成/测验未交），不是 bug。
  Future<Result<ChapterCards>> fetchCards({
    required String courseId,
    required String classId,
    required String chapterId,
    String cpi = '',
    int page = 0,
  }) async {
    final String ref = 'https://mooc1.chaoxing.com/mycourse/studentstudy'
        '?chapterId=$chapterId&courseId=$courseId&clazzid=$classId&cpi=$cpi'
        '&enc=${md5Hex('${DateTime.now().microsecondsSinceEpoch}')}&mooc2=1';
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1.chaoxing.com/knowledge/cards',
        queryParameters: <String, dynamic>{
          'clazzid': classId,
          'courseid': courseId,
          'knowledgeid': chapterId,
          'num': '$page',
          'ut': 's',
          'cpi': cpi,
          'v': '20160407-1',
        },
        options: Options(headers: <String, dynamic>{'Referer': ref}),
      );
      final String html = resp.data ?? '';
      if (_looksLikeLogin(html)) {
        return const Err<ChapterCards>('authExpired', '登录已失效');
      }
      final Map<String, dynamic>? marg = extractMarg(html);
      if (marg == null) {
        return const Err<ChapterCards>('locked', '章节未开放：上一章未完成或测验未提交');
      }
      final Map<String, dynamic> defaults =
          (marg['defaults'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final List<TaskPoint> points = <TaskPoint>[];
      for (final dynamic raw in (marg['attachments'] ?? <dynamic>[]) as List<dynamic>) {
        final Map<String, dynamic> att = (raw as Map).cast<String, dynamic>();
        final Map<String, dynamic> prop =
            (att['property'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        if (!_isTaskPoint(att, prop)) continue;
        points.add(
          TaskPoint(
            type: '${att['type'] ?? ''}',
            jobId: '${att['jobid'] ?? ''}',
            name: '${prop['name'] ?? ''}',
            objectId: '${prop['objectid'] ?? ''}',
            otherInfo: '${att['otherInfo'] ?? ''}',
            rt: '${prop['rt'] ?? '0.9'}',
            attDuration: '${att['attDuration'] ?? '0'}',
            attDurationEnc: '${att['attDurationEnc'] ?? ''}',
            videoFaceCaptureEnc: '${att['videoFaceCaptureEnc'] ?? ''}',
            // 已通过标记：卡片给了就用，没给就留 null（不猜）。
            // 语义待真实账号确认，因此上层只在明确 true 时跳过，null / false 都照常执行。
            passed: _readPassed(att, prop),
          ),
        );
      }
      return Ok<ChapterCards>(
        ChapterCards(
          reportUrl: '${defaults['reportUrl'] ?? ''}',
          fid: '${defaults['fid'] ?? '666'}',
          userId: '${defaults['userid'] ?? ''}',
          points: points,
        ),
      );
    } on DioException catch (e) {
      return Err<ChapterCards>('network', _netMessage(e));
    }
  }

  Future<Result<VideoStatus>> videoStatus(String objectId, String fid) async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1.chaoxing.com/ananas/status/$objectId',
        queryParameters: <String, dynamic>{
          'k': fid,
          'flag': 'normal',
          '_dc': '${DateTime.now().millisecondsSinceEpoch}',
        },
        options: Options(
          headers: <String, dynamic>{
            'Referer': 'https://mooc1.chaoxing.com/ananas/modules/video/index.html?v=2024',
          },
        ),
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null || json['status'] != 'success') {
        return const Err<VideoStatus>('api', '视频不可用');
      }
      final int duration = int.tryParse('${json['duration'] ?? 0}') ?? 0;
      if (duration <= 0) return const Err<VideoStatus>('api', '视频时长异常');
      return Ok<VideoStatus>(
        VideoStatus(
          objectId: '${json['objectid'] ?? objectId}',
          duration: duration,
          dtoken: '${json['dtoken'] ?? ''}',
        ),
      );
    } on DioException catch (e) {
      return Err<VideoStatus>('network', _netMessage(e));
    }
  }

  /// 上报一次进度。返回 true 表示平台判定该任务点完成。
  Future<Result<bool>> reportProgress({
    required String reportUrl,
    required String dtoken,
    required TaskPoint point,
    required String classId,
    required String uid,
    required int playTime,
    required int duration,
  }) async {
    final String enc = progressEnc(
      classId: classId,
      uid: uid,
      jobId: point.jobId,
      objectId: point.objectId,
      playTime: playTime,
      duration: duration,
    );
    final bool dragEnd = playTime >= duration;
    final String url = '$reportUrl/$dtoken';
    try {
      final Response<String> resp = await _dio.get<String>(
        url,
        queryParameters: <String, dynamic>{
          'clazzId': classId,
          'playingTime': '$playTime',
          'duration': '$duration',
          'clipTime': '0_$duration',
          'objectId': point.objectId,
          'otherInfo': point.otherInfo,
          'jobid': point.jobId,
          'userid': uid,
          'isdrag': dragEnd ? '4' : '3',
          'view': 'pc',
          'enc': enc,
          'rt': point.rt,
          'videoFaceCaptureEnc': point.videoFaceCaptureEnc,
          'dtype': 'Video',
          '_t': '${DateTime.now().millisecondsSinceEpoch}',
          'attDuration': point.attDuration,
          'attDurationEnc': point.attDurationEnc,
        },
        options: Options(
          headers: <String, dynamic>{
            'Referer': 'https://mooc1.chaoxing.com/ananas/modules/video/index.html?v=2024',
          },
        ),
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null) return const Err<bool>('parse', '进度响应无法解析');
      return Ok<bool>(json['isPassed'] == true);
    } on DioException catch (e) {
      return Err<bool>('network', _netMessage(e));
    }
  }

  /// 签到活动列表。只返回签到（type=2）与签退（type=74），其他活动类型不接。
  ///
  /// `ext` 是短时效会话数据，必须随活动一起原样带到预签到，不能缓存。
  Future<Result<List<SignActivity>>> fetchSignActivities({
    required Course course,
  }) async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist',
        queryParameters: <String, dynamic>{
          'fid': '0',
          'showNotStartedActive': '0',
          'courseId': course.courseId,
          'classId': course.classId,
          'cpi': course.cpi,
        },
        options: Options(
          headers: <String, dynamic>{'Referer': 'https://mobilelearn.chaoxing.com/'},
        ),
      );
      final String body = resp.data ?? '';
      if (_looksLikeLogin(body)) {
        return const Err<List<SignActivity>>('authExpired', '登录已失效');
      }
      final Map<String, dynamic>? json = _tryJson(body);
      if (json == null) return const Err<List<SignActivity>>('parse', '签到活动无法解析');
      final Map<String, dynamic> data =
          (json['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final List<dynamic> raw = (data['activeList'] ?? <dynamic>[]) as List<dynamic>;
      final List<SignActivity> out = <SignActivity>[];
      for (final dynamic item in raw) {
        if (item is! Map) continue;
        final Map<String, dynamic> m = item.cast<String, dynamic>();
        final String id = '${m['id'] ?? m['activeId'] ?? ''}';
        if (id.isEmpty) continue;
        final int type = int.tryParse('${m['type'] ?? 0}') ?? 0;
        if (type != 2 && type != 74) continue;
        out.add(
          SignActivity(
            activeId: id,
            name: '${m['nameOne'] ?? m['name'] ?? '签到活动'}',
            type: type,
            status: int.tryParse('${m['status'] ?? -1}') ?? -1,
            startAt: parseChaoxingTime(m['startTime']),
            endAt: parseChaoxingTime(m['endTime']),
            otherId: '${m['otherId'] ?? ''}',
            ext: '${m['ext'] ?? ''}',
          ),
        );
      }
      return Ok<List<SignActivity>>(out);
    } on DioException catch (e) {
      return Err<List<SignActivity>>('network', _netMessage(e));
    }
  }

  /// 执行一次签到：先预签到拿判定，再提交。
  ///
  /// 不做重试：同一 `activeId` 成功后重复提交会被平台判异常，
  /// 幂等由调用方（SignController）负责。
  Future<Result<SignAttempt>> signIn({
    required Course course,
    required SignActivity activity,
    required String uid,
    required String name,
    required String fid,
  }) async {
    final Map<String, dynamic> referer = <String, dynamic>{
      'Referer': 'https://mobilelearn.chaoxing.com/',
    };
    try {
      final Response<String> pre = await _dio.post<String>(
        'https://mobilelearn.chaoxing.com/newsign/preSign',
        queryParameters: <String, dynamic>{
          'courseId': course.courseId,
          'classId': course.classId,
          'activePrimaryId': activity.activeId,
          'general': '1',
          'sys': '1',
          'ls': '1',
          'appType': '15',
          'uid': uid,
          'isTeacherViewOpen': '0',
        },
        data: <String, dynamic>{'ext': activity.ext},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: referer,
        ),
      );
      final String preHtml = pre.data ?? '';
      if (_looksLikeLogin(preHtml)) {
        return const Err<SignAttempt>('authExpired', '登录已失效');
      }
      final SignAttempt? judged = judgePreSign(preHtml);
      if (judged != null) return Ok<SignAttempt>(judged);

      final Response<String> resp = await _dio.get<String>(
        'https://mobilelearn.chaoxing.com/pptSign/stuSignajax',
        queryParameters: <String, dynamic>{
          'courseId': course.courseId,
          'classId': course.classId,
          'activeId': activity.activeId,
          'uid': uid,
          'name': name,
          'fid': fid,
          'clientip': '',
          'useragent': kMobileUa,
          'appType': '15',
          // 不伪造系统 GPS：没有定位权限时按平台约定传 -1，
          // 需要定位的签到会由回执明确告知，交回用户在手机上完成。
          'latitude': '-1',
          'longitude': '-1',
          'enc': '',
          'enc2': '',
          'validate': '',
          'signCode': '',
          'objectId': activity.otherId,
          'type': '${activity.type}',
        },
        options: Options(headers: referer),
      );
      return Ok<SignAttempt>(judgeSignResponse(resp.data ?? ''));
    } on DioException catch (e) {
      return Err<SignAttempt>('network', _netMessage(e));
    }
  }

  /// 作业列表。返回 null 结构解析失败由上层转成可读错误。
  ///
  /// 提交不在本客户端做：作答页的隐藏字段集合尚未抓包确认，
  /// 猜字段提交会出现「本地以为交了、平台没收到」，比不做更糟。
  Future<Result<List<HomeworkItem>>> fetchHomeworks({
    required Course course,
  }) async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1-api.chaoxing.com/work/task-list',
        queryParameters: <String, dynamic>{
          'courseId': course.courseId,
          'classId': course.classId,
          'cpi': course.cpi,
          'ut': 's',
        },
        options: Options(
          headers: <String, dynamic>{'Referer': 'https://mooc1.chaoxing.com/'},
        ),
      );
      final String body = resp.data ?? '';
      if (_looksLikeLogin(body)) {
        return const Err<List<HomeworkItem>>('authExpired', '登录已失效');
      }
      final List<HomeworkItem>? list = parseHomeworkList(body);
      if (list == null) {
        return const Err<List<HomeworkItem>>('parse', '作业列表无法解析');
      }
      return Ok<List<HomeworkItem>>(list);
    } on DioException catch (e) {
      return Err<List<HomeworkItem>>('network', _netMessage(e));
    }
  }

  // ---------------------------------------------------------------- 工具

  /// 把 Dio 的异常翻成人能读的中文。
  ///
  /// 直接展示 e.message 时用户会看到 `SocketException: Connection refused` 这类串，
  /// 既不知道是自己网络的问题还是软件坏了，也不知道下一步该做什么。
  static String _netMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '网络超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '连不上学习通服务器，请检查网络或代理设置';
      case DioExceptionType.badCertificate:
        return '证书校验失败，当前网络可能需要登录门户';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badResponse:
        return '服务器返回异常（${e.response?.statusCode}）';
      case DioExceptionType.unknown:
        return e.message ?? '网络错误';
    }
  }

  bool _looksLikeLogin(String body) =>
      _authExpiredMarkers.any((String m) => body.contains(m));

  static bool _isDigits(String s) => s.isNotEmpty && int.tryParse(s) != null;

  /// gas/clazz 的 fields：只取章节树需要的字段，避免整包响应过大。
  static const String _chapterFields =
      'id,bbsid,classscore,isstart,allowdownload,chatid,name,state,isfiled,'
      'visiblescore,hideclazz,begindate,forbidintoclazz,'
      'coursesetting.fields(id,courseid,hiddencoursecover,coursefacecheck),'
      'course.fields(id,belongschoolid,name,infocontent,objectid,app,'
      'bulletformat,mappingcourseid,imageurl,teacherfactor,jobcount,'
      'knowledge.fields(id,name,indexOrder,parentnodeid,status,isReview,'
      'layer,label,jobcount,begintime,endtime,'
      'attachment.fields(id,type,objectid,extension).type(video)))';

  /// 从 gas/clazz 的固定层级里取出 knowledge 节点：data[0].course.data[0].knowledge.data。
  static List<Map<String, dynamic>> _chapterNodes(Map<String, dynamic> json) {
    final dynamic data = json['data'];
    if (data is! List || data.isEmpty) return const <Map<String, dynamic>>[];
    final dynamic clazz = data.first;
    if (clazz is! Map) return const <Map<String, dynamic>>[];
    final dynamic course = clazz['course'];
    if (course is! Map) return const <Map<String, dynamic>>[];
    final dynamic courseData = course['data'];
    if (courseData is! List || courseData.isEmpty) return const <Map<String, dynamic>>[];
    final dynamic firstCourse = courseData.first;
    if (firstCourse is! Map) return const <Map<String, dynamic>>[];
    final dynamic knowledge = firstCourse['knowledge'];
    if (knowledge is! Map) return const <Map<String, dynamic>>[];
    final dynamic nodes = knowledge['data'];
    if (nodes is! List) return const <Map<String, dynamic>>[];
    return nodes
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) => m.cast<String, dynamic>())
        .toList();
  }

  /// 章节标题：gas 只给 label（如 2.1）和 name，name 本身已经带编号时直接用，
  /// 避免出现「2.1 1.1近代中国…」这种双重编号；没有编号时才用 label 补顺序。
  static String _chapterTitle(Map<String, dynamic> node) {
    final String name = '${node['name'] ?? ''}'.trim();
    final String label = '${node['label'] ?? ''}'.trim();
    if (name.isEmpty) return label.isEmpty ? '章节 ${node['id']}' : label;
    if (label.isEmpty || RegExp(r'^\d').hasMatch(name)) return name;
    return '$label $name';
  }

  /// 按 label 的数字段排序（1 < 1.1 < 2）；label 缺失或相同时退回 indexorder。
  static int _compareChapterNode(Map<String, dynamic> a, Map<String, dynamic> b) {
    final List<int> la = _labelParts('${a['label'] ?? ''}');
    final List<int> lb = _labelParts('${b['label'] ?? ''}');
    for (int i = 0; i < la.length && i < lb.length; i++) {
      if (la[i] != lb[i]) return la[i].compareTo(lb[i]);
    }
    if (la.length != lb.length) return la.length.compareTo(lb.length);
    return _intValue(a['indexorder']).compareTo(_intValue(b['indexorder']));
  }

  static List<int> _labelParts(String label) {
    final List<int> out = <int>[];
    for (final RegExpMatch m in RegExp(r'\d+').allMatches(label)) {
      out.add(int.tryParse(m.group(0)!) ?? 0);
    }
    return out;
  }

  static int _intValue(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

  /// 判断一个 attachment 是不是任务点。
  ///
  /// 旧版 cards 会下发 `job: true`；新版响应里没有 `job` 字段，任务点的特征是
  /// 同时带 `jobid` 和资源标识（视频/文档有 objectid，其他类型有 otherInfo）。
  /// `job` 明确为 false/0 时仍然排除，不能把老师的非任务点素材当成任务。
  static bool _isTaskPoint(Map<String, dynamic> att, Map<String, dynamic> prop) {
    final dynamic job = att['job'];
    if (job == true || '$job' == '1') return true;
    if (job == false || '$job' == '0' || '$job' == 'false') return false;
    final String jobId = '${att['jobid'] ?? prop['jobid'] ?? ''}'.trim();
    if (jobId.isEmpty) return false;
    final String objectId = '${prop['objectid'] ?? att['objectId'] ?? ''}'.trim();
    final String otherInfo = '${att['otherInfo'] ?? ''}'.trim();
    return objectId.isNotEmpty || otherInfo.isNotEmpty;
  }

  /// 读取任务点的「已通过」标记。
  ///
  /// 已知的候选位置只有 `isPassed`（attachments 级或 property 级）。字段名未经真实账号
  /// 确认，所以这里只认明确的 true，其余一律返回 null——让上层按「不知道」处理而不是按
  /// 「未通过」处理，避免猜测导致整章重复执行。
  static bool? _readPassed(Map<String, dynamic> att, Map<String, dynamic> prop) {
    for (final dynamic v in <dynamic>[att['isPassed'], prop['isPassed']]) {
      if (v == true) return true;
      if ('$v' == '1') return true;
    }
    return null;
  }

  static Map<String, dynamic>? _tryJson(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final dynamic v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}

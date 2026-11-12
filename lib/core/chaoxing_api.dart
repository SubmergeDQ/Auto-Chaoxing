// 学习通 HTTP 客户端：只负责请求、Cookie、解析与错误归一。
// 不包含重试策略与业务循环（那是 task_runner 的事）。
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'crypto.dart';
import 'models.dart';

const String kMobileUa =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

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
    _dio.interceptors.add(CookieManager(this.cookieJar));
  }

  final CookieJar cookieJar;
  final Dio _dio;

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

  /// 章节列表：从学生课程页 HTML 里提取 chapterId 与标题。
  /// 与 core/chaoxing_core.py 的 chapters() 同一套规则。
  Future<Result<List<Chapter>>> fetchChapters({
    required String courseId,
    required String classId,
    String cpi = '',
  }) async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1.chaoxing.com/mycourse/studentcourse',
        queryParameters: <String, dynamic>{
          'courseId': courseId,
          'clazzid': classId,
          'forcedJoin': '1',
          'knowledgeid': '0',
          'ut': 's',
          'cpi': cpi,
        },
        options: Options(
          headers: <String, dynamic>{'Referer': 'https://i.chaoxing.com'},
        ),
      );
      final String html = resp.data ?? '';
      if (_looksLikeLogin(html)) {
        return const Err<List<Chapter>>('authExpired', '登录已失效');
      }
      final List<Chapter> out = <Chapter>[];
      final Set<String> seen = <String>{};
      final RegExp titled = RegExp(
        r'chapterId=(\d+)[^>]*>\s*(?:<[^>]+>\s*)*([^<]{1,60})',
      );
      for (final RegExpMatch m in titled.allMatches(html)) {
        final String id = m.group(1) ?? '';
        final String title = (m.group(2) ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        if (id.isEmpty || !seen.add(id)) continue;
        out.add(Chapter(chapterId: id, title: title.isEmpty ? '章节 $id' : title));
      }
      if (out.isEmpty) {
        // mooc2 折叠结构里标题和 anchor 不同行，退化为只取 id。
        for (final RegExpMatch m in RegExp(r'chapterId=(\d+)').allMatches(html)) {
          final String id = m.group(1) ?? '';
          if (id.isNotEmpty && seen.add(id)) {
            out.add(Chapter(chapterId: id, title: '章节 $id'));
          }
        }
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
        if (att['job'] != true) continue;
        final Map<String, dynamic> prop =
            (att['property'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
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

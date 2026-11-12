// 登录链路实测探针：把每一步的原始响应打出来，用来定位「登录到底卡在哪一步」。
// 仅开发期使用，不进入 App 构建产物。
//
// 用法：dart run tool/login_probe.dart <账号> <密码>
import 'dart:convert';
import 'dart:io';

import 'package:auto_chaoxing/core/crypto.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

const String _ua =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

String _cut(String? s, [int n = 600]) {
  final String t = s ?? '';
  final String one = t.replaceAll(RegExp(r'\s+'), ' ');
  return one.length <= n ? one : '${one.substring(0, n)}…(${one.length} chars)';
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/login_probe.dart <账号> <密码>');
    exit(2);
  }
  final String user = args[0];
  final String pass = args[1];

  stdout.writeln('== 环境 ==');
  stdout.writeln('  dart: ${Platform.version.split(' ').first}');
  stdout.writeln('  HTTP_PROXY: ${Platform.environment['HTTP_PROXY'] ?? '(none)'}');
  stdout.writeln('  uname 加密后长度: ${aesCbcBase64(user).length}');

  final CookieJar jar = CookieJar();
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (int? s) => s != null && s < 500,
      headers: <String, dynamic>{
        'User-Agent': _ua,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'X-Requested-With': 'com.chaoxing.mobile',
      },
    ),
  );
  dio.interceptors.add(CookieManager(jar));

  // 步骤 1：先访问登录页，拿 passport 侧的初始 cookie（_uid / route / fid 等）
  stdout.writeln('\n== 1. GET passport 登录页 ==');
  try {
    final Response<String> r = await dio.get<String>(
      'https://passport2.chaoxing.com/login',
      queryParameters: <String, dynamic>{'fid': '', 'refer': 'https://i.chaoxing.com'},
    );
    stdout.writeln('  status=${r.statusCode} len=${r.data?.length ?? 0}');
    stdout.writeln('  body: ${_cut(r.data, 240)}');
    final List<Cookie> cs = await jar.loadForRequest(
      Uri.parse('https://passport2.chaoxing.com/login'),
    );
    stdout.writeln('  cookies(${cs.length}): ${cs.map((Cookie c) => c.name).join(',')}');
  } catch (e) {
    stdout.writeln('  !! $e');
  }

  // 步骤 2：提交账号密码
  stdout.writeln('\n== 2. POST fanyalogin ==');
  String? loginBody;
  try {
    final Response<String> r = await dio.post<String>(
      'https://passport2.chaoxing.com/fanyalogin',
      data: <String, dynamic>{
        'fid': '-1',
        'refer': 'https://i.chaoxing.com',
        't': 'true',
        'forbidotherlogin': '0',
        'validate': '',
        'uname': aesCbcBase64(user.trim()),
        'password': aesCbcBase64(pass),
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: <String, dynamic>{
          'Origin': 'https://passport2.chaoxing.com',
          'Referer': 'https://passport2.chaoxing.com/login?fid=&refer=https%3A%2F%2Fi.chaoxing.com',
        },
      ),
    );
    loginBody = r.data;
    stdout.writeln('  status=${r.statusCode}');
    stdout.writeln('  body: ${_cut(r.data, 800)}');
    final List<Cookie> cs = await jar.loadForRequest(
      Uri.parse('https://passport2.chaoxing.com/fanyalogin'),
    );
    stdout.writeln('  cookies(${cs.length}): ${cs.map((Cookie c) => c.name).join(',')}');
  } on DioException catch (e) {
    stdout.writeln('  !! ${e.type} ${e.message}');
    if (e.response != null) {
      stdout.writeln('  resp: ${_cut(e.response?.data?.toString(), 400)}');
    }
  }
  stdout.writeln('  loginBody 可解析 JSON: '
      '${loginBody != null && !loginBody.trimLeft().startsWith('<')}');

  // 步骤 3：取账号信息
  stdout.writeln('\n== 3. GET userLogin4Uname.do ==');
  try {
    final Response<String> r = await dio.get<String>(
      'https://sso.chaoxing.com/apis/login/userLogin4Uname.do',
    );
    stdout.writeln('  status=${r.statusCode} len=${r.data?.length ?? 0}');
    final dynamic j = jsonDecode(r.data ?? '{}');
    if (j is Map) {
      stdout.writeln('  keys=${j.keys.toList()}');
      stdout.writeln('  result=${j['result']} errorMsg=${j['errorMsg']}');
      final dynamic m = j['msg'];
      if (m is Map) {
        stdout.writeln('  msg.uid=${m['uid']} msg.puid=${m['puid']} '
            'msg.name=${m['name']} msg.phone=${m['phone']}');
        stdout.writeln('  msg keys=${m.keys.toList()}');
      }
    }
    stdout.writeln('  tail: ${_cut((r.data ?? '').length > 200 ? (r.data ?? '').substring((r.data ?? '').length - 200) : r.data, 300)}');
  } on DioException catch (e) {
    stdout.writeln('  !! ${e.type} ${e.message}');
  }

  // 步骤 4：课程列表
  stdout.writeln('\n== 4. GET backclazzdata ==');
  try {
    final Response<String> r = await dio.get<String>(
      'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
      queryParameters: <String, dynamic>{'view': 'json', 'rss': '1'},
    );
    stdout.writeln('  status=${r.statusCode} len=${r.data?.length ?? 0}');
    stdout.writeln('  body: ${_cut(r.data, 500)}');
  } on DioException catch (e) {
    stdout.writeln('  !! ${e.type} ${e.message}');
  }

  // 步骤 4b：学生课程列表页（另一条取课路径）
  stdout.writeln('\n== 4b. GET courselistdata ==');
  try {
    final Response<String> r = await dio.get<String>(
      'https://mooc1.chaoxing.com/visit/courselistdata',
      queryParameters: <String, dynamic>{
        'courseType': '1',
        'courseFolderId': '0',
        'baseEducation': '0',
        'superstarClass': '0',
      },
      options: Options(headers: <String, dynamic>{'Referer': 'https://mooc1.chaoxing.com/'}),
    );
    final String b = r.data ?? '';
    stdout.writeln('  status=${r.statusCode} len=${b.length}');
    final Iterable<RegExpMatch> ids =
        RegExp(r'courseid=(\d+)[^>]{0,80}').allMatches(b).take(6);
    stdout.writeln('  courseid 命中: ${ids.length}');
    for (final RegExpMatch m in RegExp(r'courseid=(\d+)&clazzid=(\d+)').allMatches(b).take(6)) {
      stdout.writeln('    course=${m.group(1)} clazz=${m.group(2)}');
    }
    stdout.writeln('  body: ${_cut(b, 400)}');
  } on DioException catch (e) {
    stdout.writeln('  !! ${e.type} ${e.message}');
  }

  // 步骤 5：i.chaoxing.com 首页（登录态最直观的证据）
  stdout.writeln('\n== 5. GET i.chaoxing.com ==');
  try {
    final Response<String> r = await dio.get<String>(
      'https://i.chaoxing.com/base/index',
      options: Options(followRedirects: false),
    );
    stdout.writeln('  status=${r.statusCode} len=${r.data?.length ?? 0}');
    stdout.writeln('  location: ${r.headers.value('location') ?? '-'}');
    stdout.writeln('  body: ${_cut(r.data, 300)}');
  } on DioException catch (e) {
    stdout.writeln('  !! ${e.type} ${e.message}');
  }

  stdout.writeln('\n== 汇总 ==');
  final List<Cookie> all = <Cookie>[];
  for (final String host in <String>['chaoxing.com', 'passport2.chaoxing.com', 'i.chaoxing.com']) {
    all.addAll(await jar.loadForRequest(Uri.parse('https://$host/')));
  }
  final List<String> names = all.map((Cookie c) => c.name).toSet().toList()..sort();
  stdout.writeln('  全部 cookie 名: ${names.join(', ')}');
  stdout.writeln('  关键项 _uid=${names.contains('_uid')} '
      '_d=${names.contains('_d')} fid=${names.contains('fid')} '
      'uf=${names.contains('uf')} cx_p_token=${names.contains('cx_p_token')}');
  exit(0);
}

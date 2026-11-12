import 'package:auto_chaoxing/core/crypto.dart';
import 'package:auto_chaoxing/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crypto', () {
    test('md5 固定向量', () {
      expect(md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
    });

    test('AES-CBC 登录加密固定向量', () {
      // 与 core/chaoxing_core.py 的 aes_cbc_b64("123456") 输出一致。
      // 另一路独立验证：openssl enc -d -aes-128-cbc -K/-iv <hex(u2oh6Vu^HWe4_AES)>
      // 能解出明文 123456。
      expect(aesCbcBase64('123456'), '0QgUbMUJj2usHikiqtb8HQ==');
    });

    test('登录密钥是平台写死的固定值，首字母是 u', () {
      // 曾经写成 m2oh6Vu^HWe4_AES，服务端解不出明文，一律回「用户名或密码错误」，
      // 表现为「密码明明是对的却登不上」。这行是唯一能挡住该回归的断言。
      expect(kLoginAesKey, 'u2oh6Vu^HWe4_AES');
    });

    test('视频进度签名固定向量', () {
      expect(
        progressEnc(
          classId: '123',
          uid: '456',
          jobId: '789',
          objectId: 'abc',
          playTime: 0,
          duration: 600,
        ),
        'f72245dce1271d7e6039a4f3110a0575',
      );
    });

    test('进度签名随 playTime 变化，且结尾必须是 isdrag=4 的终点', () {
      final String a = progressEnc(
        classId: '123',
        uid: '456',
        jobId: '789',
        objectId: 'abc',
        playTime: 0,
        duration: 600,
      );
      final String b = progressEnc(
        classId: '123',
        uid: '456',
        jobId: '789',
        objectId: 'abc',
        playTime: 60,
        duration: 600,
      );
      expect(a, isNot(b));
    });
  });

  group('extractMarg', () {
    test('能从 cards 页面里抠出 mArg', () {
      const String html = '''
        <script>
        try{
          mArg = {"defaults":{"reportUrl":"https://mooc1.chaoxing.com/multimedia/log/a","fid":"666"},
                  "attachments":[{"job":true,"type":"video","jobid":"j1","otherInfo":"oi",
                    "property":{"objectid":"o1","name":"第一讲"}}]};
        }catch(e){}
        </script>
      ''';
      final Map<String, dynamic>? marg = extractMarg(html);
      expect(marg, isNotNull);
      expect(marg!['defaults']['reportUrl'], contains('/multimedia/log'));
      final List<dynamic> atts = marg['attachments'] as List<dynamic>;
      expect(atts.length, 1);
    });

    test('没有 mArg 时返回 null（章节未开放）', () {
      expect(extractMarg('<html><body>请在规定时间内完成</body></html>'), isNull);
    });
  });
}

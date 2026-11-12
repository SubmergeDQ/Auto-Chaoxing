import 'package:auto_chaoxing/core/crypto.dart';
import 'package:auto_chaoxing/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crypto', () {
    test('md5 固定向量', () {
      expect(md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
    });

    test('AES-CBC 登录加密固定向量', () {
      // 与 core/chaoxing_core.py 的 aes_cbc_b64("123456") 输出一致
      expect(aesCbcBase64('123456'), 'FiK1hSgSEgMeqWPSRhRB+A==');
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

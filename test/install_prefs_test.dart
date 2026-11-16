import 'dart:io';

import 'package:auto_chaoxing/platform/install_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('偏好文件写在给定目录，重启后还能读回', () async {
    final Directory dir = await Directory.systemTemp.createTemp('acx_prefs_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final File file = File('${dir.path}${Platform.pathSeparator}shared_preferences.json');

    final InstallDirPreferencesStore first = InstallDirPreferencesStore(file);
    expect(await first.setValue('String', 'flutter.last_username', '13800000000'), isTrue);
    expect(await first.setValue('Int', 'flutter.last_check', 1700000000000), isTrue);

    expect(await first.getAll(), <String, Object>{
      'flutter.last_username': '13800000000',
      'flutter.last_check': 1700000000000,
    });

    // 新实例模拟重启：数据只能从文件恢复，内存缓存帮不上忙。
    final InstallDirPreferencesStore second = InstallDirPreferencesStore(file);
    expect((await second.getAll())['flutter.last_username'], '13800000000');
    expect((await second.getAll())['flutter.last_check'], 1700000000000);

    expect(await second.remove('flutter.last_username'), isTrue);
    expect(await second.getAll(), <String, Object>{
      'flutter.last_check': 1700000000000,
    });
  });
}

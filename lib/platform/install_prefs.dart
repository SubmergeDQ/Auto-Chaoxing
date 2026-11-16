// 安装目录内的偏好存储。
//
// shared_preferences 的 Windows 实现默认写 %APPDATA%，与「数据跟着安装位置走」
// 冲突。这里替换 SharedPreferencesStorePlatform，把同样的键值落到
// <安装目录>\userdata\shared_preferences.json，调用方的 API 不变。
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

class InstallDirPreferencesStore extends SharedPreferencesStorePlatform {
  InstallDirPreferencesStore(this.file);

  final File file;

  /// 与平台实现一致的旧版前缀；读写过滤都按它来。
  static const String _prefix = 'flutter.';

  Map<String, Object>? _cache;

  Future<Map<String, Object>> _load() async {
    final Map<String, Object>? cached = _cache;
    if (cached != null) return cached;

    final Map<String, Object> data = <String, Object>{};
    try {
      if (await file.exists()) {
        final dynamic decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<dynamic, dynamic>) {
          decoded.forEach((dynamic key, dynamic value) {
            if (value is String || value is int || value is double || value is bool) {
              data['$key'] = value as Object;
            } else if (value is List<dynamic>) {
              data['$key'] = value.map((dynamic e) => '$e').toList();
            }
          });
        }
      }
    } catch (_) {
      // 文件损坏或写到一半：从空开始，不能因为设置文件让应用起不来。
    }
    _cache = data;
    return data;
  }

  Future<bool> _save() async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_cache ?? <String, Object>{}), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> clear() => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: _prefix)),
      );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final Map<String, Object> data = await _load();
    final PreferencesFilter filter = parameters.filter;
    data.removeWhere(
      (String key, Object _) =>
          key.startsWith(filter.prefix) &&
          (filter.allowList == null || filter.allowList!.contains(key)),
    );
    return _save();
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: _prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) async {
    final Map<String, Object> data = await _load();
    final PreferencesFilter filter = parameters.filter;
    return <String, Object>{
      for (final MapEntry<String, Object> entry in data.entries)
        if (entry.key.startsWith(filter.prefix) &&
            (filter.allowList == null || filter.allowList!.contains(entry.key)))
          entry.key: entry.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    final Map<String, Object> data = await _load();
    data.remove(key);
    return _save();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final Map<String, Object> data = await _load();
    data[key] = value;
    return _save();
  }
}

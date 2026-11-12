// 版本与发布模型的纯 Dart 部分：不联网、不碰平台，便于直接单测。
//
// 发布约定（写在仓库 README 里，检查更新按这个约定挑资产）：
//   Android  → 任意以 .apk 结尾的资产，优先名字里带 arm64-v8a 的
//   Windows  → 优先 auto-chaoxing-setup-*.exe（安装器），没有则退回 *windows*.zip
// 版本号取 Release 的 tag，允许带前缀 v，例如 v0.4.0 与 0.4.0 等价。
import 'dart:math' as math;

/// 需要区分的两种产物。桌面端以后若要加 macOS，在这里扩。
enum UpdatePlatform { android, windows }

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size});

  final String name;
  final String url;
  final int size;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        name: '${json['name'] ?? ''}',
        url: '${json['browser_download_url'] ?? ''}',
        size: int.tryParse('${json['size'] ?? 0}') ?? 0,
      );

  String get lowerName => name.toLowerCase();

  bool get isApk => lowerName.endsWith('.apk');

  bool get isInstaller => lowerName.endsWith('.exe');

  bool get isZip => lowerName.endsWith('.zip');

  /// 形如 `m2` 的说明，用来在界面上让用户知道自己下的是哪个架构。
  String get sizeLabel {
    if (size <= 0) return '';
    final double mb = size / 1024 / 1024;
    return mb >= 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.toStringAsFixed(2)} MB';
  }
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.title,
    required this.notes,
    required this.publishedAt,
    required this.assets,
  });

  final String tag;
  final String title;
  final String notes;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  /// 去掉前缀 v 的版本号，用于比较与展示。
  String get version => normalizeVersion(tag);

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = (json['assets'] as List<dynamic>?) ?? <dynamic>[];
    return AppRelease(
      tag: '${json['tag_name'] ?? ''}',
      title: '${json['name'] ?? json['tag_name'] ?? ''}',
      notes: '${json['body'] ?? ''}',
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
      assets: raw
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => ReleaseAsset.fromJson(m.cast<String, dynamic>()))
          .where((ReleaseAsset a) => a.url.isNotEmpty)
          .toList(),
    );
  }

  /// 按平台挑一个最合适的下载资产。挑不到返回 null（例如只传了源码包）。
  ReleaseAsset? assetFor(UpdatePlatform platform) {
    return switch (platform) {
      UpdatePlatform.android => _pick(
          assets.where((ReleaseAsset a) => a.isApk).toList(),
          // 模拟器/真机大多数是 arm64；名字里没写架构的 universal 包排在后面兜底。
          prefer: (ReleaseAsset a) => a.lowerName.contains('arm64') || a.lowerName.contains('universal'),
        ),
      UpdatePlatform.windows => _pick(
          assets.where((ReleaseAsset a) => a.isInstaller).toList(),
          prefer: (ReleaseAsset a) => a.lowerName.contains('setup') || a.lowerName.contains('install'),
        ) ??
          _pick(
            assets.where((ReleaseAsset a) => a.isZip).toList(),
            prefer: (ReleaseAsset a) => a.lowerName.contains('windows'),
          ),
    };
  }

  static ReleaseAsset? _pick(
    List<ReleaseAsset> list, {
    required bool Function(ReleaseAsset) prefer,
  }) {
    if (list.isEmpty) return null;
    final List<ReleaseAsset> preferred = list.where(prefer).toList();
    return preferred.isNotEmpty ? preferred.first : list.first;
  }
}

/// `v0.4.1` → `0.4.1`。只去掉开头的 v/V，其余原样保留（可能是 `1.0.0-beta`）。
String normalizeVersion(String raw) {
  final String t = raw.trim();
  if (t.isEmpty) return '';
  return (t.startsWith('v') || t.startsWith('V')) ? t.substring(1) : t;
}

/// 比较两个版本号：a 比 b 新返回正数，相同返回 0。
///
/// 逐段按数字比，`0.3.10` 大于 `0.3.9`（字符串比较会得出相反结论）。
/// 段数不同时短的补 0，`1.2` 与 `1.2.0` 视为相同。带 `-beta` 这类后缀的段
/// 取数字前缀，`1.0.0-beta` 与 `1.0.0` 比会被当作相同——本项目不用预发布版，
/// 这里宁可把它当正式版，也不要在比较里抛出异常。
int compareVersions(String a, String b) {
  final List<int> pa = _parse(a);
  final List<int> pb = _parse(b);
  final int n = math.max(pa.length, pb.length);
  for (int i = 0; i < n; i++) {
    final int va = i < pa.length ? pa[i] : 0;
    final int vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<int> _parse(String raw) {
  final String t = normalizeVersion(raw);
  if (t.isEmpty) return const <int>[];
  return t
      .split('.')
      .map((String seg) {
        final RegExpMatch? m = RegExp(r'^\d+').firstMatch(seg.trim());
        return m == null ? 0 : (int.tryParse(m.group(0)!) ?? 0);
      })
      .toList();
}

/// 检查更新的节流：5 分钟内只查一次。
///
/// 需求原话是「每次打开应用检查，但 5 分钟内只查一次」。放在这里而不是 UI 里，
/// 是因为调用点有两个（启动时静默检查、关于页手动点），两边必须共用同一个时间戳。
const Duration kUpdateCheckWindow = Duration(minutes: 5);

class UpdateThrottle {
  const UpdateThrottle({required this.read, required this.write});

  /// 上次检查时间；没查过返回 null。
  final Future<DateTime?> Function() read;
  final Future<void> Function(DateTime) write;

  /// force 用于用户主动点「检查更新」——手动操作不该被 5 分钟窗口挡住。
  Future<bool> shouldCheck(DateTime now, {bool force = false}) async {
    if (force) return true;
    final DateTime? last = await read();
    if (last == null) return true;
    return now.difference(last) >= kUpdateCheckWindow;
  }

  Future<void> markChecked(DateTime now) => write(now);
}

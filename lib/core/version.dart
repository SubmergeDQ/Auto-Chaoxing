// 客户端自己的版本号。
//
// 为什么不用 package_info_plus：它要再加一层原生插件，而这里只需要一个常量。
// 代价是必须和 pubspec.yaml 手动同步，所以 test/version_test.dart 会读 pubspec
// 做断言——忘了改会直接测试失败，而不是发出去一个「检查更新永远说已最新」的包。
const String kAppVersion = '0.4.1';

/// 版本号的展示形式（带 v，和 Release tag 的写法一致）。
String get kAppVersionLabel => 'v$kAppVersion';

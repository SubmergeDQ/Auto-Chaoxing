# 05 · Flutter 双端（Android + Windows）可行性评估

## 结论

**可行，评分 8/10。** 业务与协议部分是纯 Dart + HTTP，双端零差异；
真正需要小心的是**四个平台能力**：后台长任务、WebView 注入、Cookie 同步、通知。
把这四项收敛到一个 `PlatformServices` 接口后，双端开发成本比单端只增加约 20–30%。

**不推荐**用 Flutter 的地方：如果你后面想做「Hook 系统定位」「无障碍点击」这类侵入式能力——
Flutter 也能做，但要写大量原生插件，那时不如直接 Kotlin。本项目不走那条路。

---

## 一、为什么这套业务天然适合 Flutter

| 业务特征 | 对框架的要求 | Flutter 表现 |
|---|---|---|
| 协议 = HTTPS + 表单 + MD5/AES | 任意语言都能做 | ✅ dart:io + pointycastle，双端同一份代码 |
| 页面解析 = 正则 + HTML | 无原生依赖 | ✅ 纯 Dart |
| UI = 列表 + 日志 + 进度 | 跨端一致即可 | ✅ 强项 |
| 长任务 = 前台服务/后台线程 | 平台相关 | ⚠️ 需要插件，Android 有成熟方案 |
| 少量 WebView 注入 | 平台相关 | ⚠️ Android 好，Windows 弱 |
| 不需要 root / 无障碍 / 系统 hook | — | ✅ 全部满足 |

关键判断：**这个项目的"重"在协议和编排，不在原生能力**。协议一旦用 Dart 写对，双端就是白送。

---

## 二、平台差异矩阵

| 能力 | Android | Windows | 统一策略 |
|---|---|---|---|
| 长任务后台 | 前台服务 + 常驻通知，需引导关电池优化 | 进程不被杀，Isolate 直接跑 | 抽象 `BackgroundRunner.start(task)` |
| 通知 | `flutter_local_notifications` 完整 | 支持有限（需 toast/托盘兜底） | 抽象 `Notifier` |
| WebView | `flutter_inappwebview`：JS 注入、CookieManager、请求拦截 | `webview_windows`：基本只有 `ExecuteScriptAsync`，无 userScript、Cookie API 弱 | 抽象 `WebAuth`；Windows 版降级为"登录用 + 作业走 HTTP" |
| Cookie 共享 | 可从 CookieManager 导出 | 基本不可用 | **以 dio 的 CookieJar 为唯一真相**，WebView 只做一次性登录 |
| 安全存储 | Keystore（`flutter_secure_storage`） | DPAPI（同库支持） | 直接复用 |
| 托盘/开机自启 | 不适用 | `tray_manager` / 注册表 | 仅 Windows 分支启用 |
| 打包 | APK（按 ABI 分包） | MSIX / zip（未签名会有 SmartScreen 提示） | CI 两段 |

> 唯一"真差异"在 WebView。这也是为什么架构上**作业提交不依赖 WebView 作为唯一路径**：
> Android 走 WebView 保真，Windows 走纯 HTTP（实验性）；两条路都失败就停下来让人接手。

---

## 三、技术选型

| 用途 | 选型 | 备选 | 备注 |
|---|---|---|---|
| 网络 | `dio` + `cookie_jar` + `dio_cookie_manager` | `http` | 需要拦截器做 UA/Referer/节流 |
| 加密 | `pointycastle` + `crypto` | `encrypt` | AES-CBC 与 MD5 都是纯 Dart，双端一致 |
| 存储 | `drift`（sqlite） | `hive` | Windows 需 `sqlite3_flutter_libs` |
| 安全存储 | `flutter_secure_storage` | 自写平台通道 | 双端都支持 |
| 状态管理 | `riverpod` | `provider` / `bloc` | 任务状态机用 `StateNotifier` 合适 |
| 后台（Android） | `flutter_foreground_task` | `flutter_background_service` | 前者对前台服务封装更完整 |
| WebView（Android） | `flutter_inappwebview` | `webview_flutter` | 需要 `userScript` 与 CookieManager |
| WebView（Windows） | `webview_windows` | 无（或自建 WebView2 插件） | 能力有限，仅登录兜底 |
| 通知 | `flutter_local_notifications` | 平台通道 | Windows 兜底用托盘 |
| 日志 | `logger` + 自写环形缓冲 | — | 必须做脱敏 |

依赖策略：**先 `any` 跑通 `pub get`，立刻回填精确版本并提交 `pubspec.lock`**。
这类插件版本漂移很快，"在我机器上能编"是最常见的伪成功。

---

## 四、Windows 端要注意的现实

1. **WebView2 不是 Gecko**：没有 `userScript` 级别的注入，也没有成熟的 Cookie 导出。
   任何"依赖注入脚本才能跑"的功能，在 Windows 上都要有第二条路。
2. **首次运行需要 WebView2 运行时**：Win10 较老版本可能没有，安装包里要检测并提示。
3. **未签名 exe 会被 SmartScreen 拦**：不是 bug，用户点"仍要运行"即可；要避免就买证书。
4. **高 DPI**：Windows 缩放下字体与间距和手机不同，布局用自适应断点而不是固定像素。
5. **不需要管理员权限**：本项目不写注册表（除可选的开机自启）、不装服务。

## 五、Android 端要注意的现实

1. **国产 ROM 的后台管理**是最大敌人：小米/华为/OPPO 需要引导用户把 App 加入"自启动/省电白名单"，
   否则前台服务也会被杀。首次启动做一次引导页。
2. **前台服务必须带持续通知**（Android 14 起类型声明要求 `dataSync`/`specialUse`），
   通知要能一键停止，否则用户会卸载。
3. **Android 14 的 `POST_NOTIFICATIONS` 运行时权限**必须申请，被拒就没法提醒签到。
4. **Doze 模式**：长时间挂机建议持有 `PARTIAL_WAKE_LOCK`（用插件封装），只在任务运行时持有。
5. **不要在模拟器上验收签到**：定位参数、后台策略、网络环境都和真机不同。

---

## 六、工期影响

| 工作 | 单端（Android） | 双端（+Windows） |
|---|---|---|
| 协议与核心 | 2 周 | 2 周（不变） |
| UI | 1 周 | 1.2 周（自适应布局 + 托盘） |
| 平台能力 | 1 周（前台服务） | 1.5 周（Windows 降级实现） |
| 打包发布 | 0.5 周 | 1 周（MSIX + 签名 + CI） |
| **合计** | **约 4.5 周** | **约 5.7 周（+25%）** |

结论：**双端只多四分之一的工作量，但你得到了"电脑上挂机"这个真正好用的场景**——
Windows 端没有后台限制，挂一整晚不会断，这是手机做不到的。

---

## 七、如果后面发现 Flutter 不合适

有三个明确的"退出信号"，出现任意一个就该考虑换栈：

1. 需要 Hook 系统定位 / 无障碍自动化（Flutter 要写大量原生插件）；
2. Windows 端必须在 WebView 里跑油猴级脚本（WebView2 包装库撑不住）；
3. 包体积/启动速度成为硬指标（Flutter 桌面版天生偏大）。

真到那一步，替代路线是：**Kotlin（Android）+ WinUI3 或 Tauri（Windows），共享一份协议文档与测试向量**。
好消息是——本仓库把协议、签名、状态机都写成了与框架无关的形态（`docs/03` + `test/crypto_test.dart`），
换栈时这一层可以整段搬走。

---

## 八、决策备忘

- ✅ 采用 Flutter：共享 UI 与协议、开发速度快、双端体验一致。
- ✅ 平台能力全部抽象到 `PlatformServices`，禁止在业务层出现 `Platform.isAndroid`。
- ✅ WebView 只做"登录 + Android 作业提交"，其余全走 HTTP。
- ✅ 先做 Android（验收刷课与签到），Windows 端在 M5 补齐。
- ❌ 不做自动交卷；❌ 不做 Hook/无障碍；❌ 不把 cookie 当日志打。

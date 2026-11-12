# Auto-Chaoxing

跨平台（Android / Windows）的**学习通课程自动化客户端**。

不依赖任何宿主 App、不需要 root、不需要无障碍服务：直接复刻学习通网页端协议，
在本地完成「章节任务点、视频进度、章节测验、作业、签到监听」这些重复劳动，
并用原生 UI 把进度、日志和结果摊开给你看。

> **当前状态（0.2.0）**：M0 协议验证、M1 双端工程与「登录 → 课程 → 章节 → 任务点」只读工作台已完成。
> 工程可编译、可运行、可测试；**自动执行（M2）、作业 / 测验 / 签到仍未接线**，
> 界面里的任务点是只读视图，不会替你完成任何东西。协议细节见 `docs/03-协议与接口.md`。

---

## 为什么重写，而不是做个插件

学习通自动化通常有两种形态：油猴脚本（依赖浏览器）与宿主插件（依赖某个 App 的私有运行时）。
两者都有同一个问题——**你的自动化跑在别人的容器里**：容器升级、改协议、下架，你就一起停摆。

本项目的取舍：

| | 油猴脚本 | 宿主插件 | Auto-Chaoxing |
|---|---|---|---|
| 依赖浏览器/宿主 | 是 | 是 | 否 |
| 后台熄屏运行 | 难 | 看宿主 | 前台服务，可熄屏 |
| 协议可控可调试 | 否 | 否 | 是，全部走本地日志 |
| 双端（手机+电脑） | 仅浏览器 | 仅那个 App | Android + Windows 同源 |
| 维护成本 | 跟页面改版 | 跟宿主 API | 跟协议变更（更稳定的一层） |

核心事实：**学习通的视频进度是可以本地算出来的**。
进度上报只需要 `md5("[classId][uid][jobid][objectid][playTime][盐][duration][0_duration]")`，
不发一个字节的视频流量就能让任务点变绿。这条链路不需要浏览器，只需要 cookie 和 md5。

---

## 功能矩阵

| 功能 | Android | Windows | 说明 |
|---|---|---|---|
| 账号登录（密码 AES-CBC） | ✅ | ✅ | 已实现；验证码 / 二次验证需人工在浏览器完成一次登录 |
| 课程 / 章节树 / 任务点 | ✅ | ✅ | 已实现，只读查看；`backclazzdata` + `studentcourse` + `knowledge/cards` |
| 协议自检 | ✅ | ✅ | 本地跑 AES-CBC 与进度签名固定向量，与 Python 参考实现对齐 |
| 视频任务点自动完成 | 🚧 | 🚧 | 协议与 `TaskRunner` 已落地，UI 尚未接线 |
| 文档 / 阅读任务点 | 🚧 | 🚧 | 停留上报待实测 |
| 章节测验自动作答 | ⏳ | ⏳ | 题目解析 + 题库 + 提交 |
| 作业自动作答与提交 | ⏳ | ⚠️ | Windows 走纯 HTTP，Android 用隐藏 WebView 保真 |
| 签到监听 + 通知 | ⏳ | ➖ | Windows 无「手机签到」语义，仅保留手动签到 |
| 考试提醒 | ⏳ | ⏳ | 只提醒，不自动交卷 |
| 账号隔离 / 多账号 | ⏳ | ⏳ | 每账号独立 cookie 与数据目录 |

图例：✅ 已实现可运行、🚧 协议已实现但未接线、⏳ 未开始、⚠️ 降级实现、➖ 不适用

---

## 快速开始

```bash
# 需要 Flutter 3.24+ / Dart 3.5+（已在 Flutter 3.47.9 / Dart 3.13.7 上验证）
# Windows Git Bash 下按本机 SDK 位置调整：
export PATH="/d/dev/flutter/bin:/d/dev/flutter/bin/cache/dart-sdk/bin:$PATH"

flutter pub get
flutter run -d windows      # Windows 桌面（需要 VS 2022 C++ 工具链）
flutter run -d android      # Android 真机/模拟器
```

本地检查：

```bash
flutter analyze
flutter test
```

### Windows 本地环境的三个坑

1. **路径含中文**：`flutter analyze` 的 analysis server 可能崩溃（LSP 消息被截断）。把仓库复制到一个纯 ASCII 路径再跑 analyze；CI 的 Linux runner 不受影响，代码本身没有问题。
2. **设了代理**：`flutter test` 会报 `Invalid WebSocket upgrade request`，因为本地回环握手被 `HTTP_PROXY` 劫持。运行时清空代理变量并加 `NO_PROXY=127.0.0.1,localhost`：
   ```bash
   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
       NO_PROXY=127.0.0.1,localhost flutter test
   ```
3. **Windows 构建**：`flutter doctor` 的 Windows / Visual Studio 检查依赖 `reg.exe` 与 `wmic.exe`，受限环境里这两项会报错，不代表项目配置有问题。

当前可执行的纯 Python 协议自检（不需要 App）：

```bash
cd core
python3 chaoxing_core.py login <手机号> <密码>
python3 chaoxing_core.py courses
python3 chaoxing_core.py video <courseId> <classId> <chapterId>
```

---

## 目录结构

```
lib/
  main.dart                 # 入口：创建 AppState 并挂载 AppShell
  state/app_state.dart      # 账号 / 课程 / 章节 / 任务点状态（ChangeNotifier，可注入 api）
  core/
    crypto.dart             # AES-CBC / MD5 / 进度签名
    chaoxing_api.dart       # 登录、课程、章节列表、章节卡片、视频状态与进度上报
    models.dart             # 数据模型
    task_runner.dart        # 任务编排（串行队列、节流、断点续跑）
  ui/
    theme.dart              # 设计变量单一来源（颜色 / 间距 / 圆角 / 状态语义 / 主题）
    widgets.dart            # 状态徽章、卡片、空态、错误态、指标、账号标记、顶栏
    app_shell.dart          # 自适应导航（宽屏侧栏 / 窄屏底栏）
    courses_page.dart       # 课程工作台 + 登录对话框（代表性页面）
    chapter_view.dart       # 章节详情（宽屏伴随面板 / 窄屏下钻页）
    aux_pages.dart          # 协议自检页、设置页
  platform/
    platform_services.dart  # 平台差异抽象（后台服务 / WebView / 通知 / 托盘）
android/ windows/           # 双端平台工程（flutter create 生成，含 INTERNET 权限）
docs/
  01-架构设计.md
  02-开发流程.md
  03-协议与接口.md
  04-难点与注意事项.md
  05-Flutter双端可行性评估.md
core/                       # 纯 Python 协议验证脚本（不含 App 依赖）
test/
  crypto_test.dart          # 签名与加密固定向量
  app_state_test.dart       # 状态流转
  ui_states_test.dart       # 关键界面状态
  support/fake_api.dart     # 可注入的假协议实现与示例数据
  visual_capture.dart       # 视觉取证（显式运行，产物 test/goldens/ 不入库）
```

---

## 验证与视觉取证

`test/visual_capture.dart` 用 Flutter 真实渲染导出 `1440×900` 桌面与 `390×844` 移动端标准视口截图，
覆盖课程工作台、未登录空态、协议自检、设置页、移动端章节下钻：

```bash
flutter test test/visual_capture.dart --update-goldens
```

- 产物在 `test/goldens/`，属于过程文件，已加入 `.gitignore`。
- `flutter_test` 默认使用 Ahem 占位字体，中文和图标会变成方块；取证脚本会注入系统等线字体与 `MaterialIcons`，只在测试环境生效，不影响正式包。
- 截图使用 `test/support/fake_api.dart` 的**示例数据**，不是真实账号内容；界面上没有「已完成」这类未经平台确认的状态。

---

## 技术栈

- **Flutter 3.24+ / Dart 3.5+**，单代码库双端，Material 3 自适应布局
- **dio + cookie_jar**：自管 CookieJar，不依赖平台 WebView 的会话
- **pointycastle**：AES-CBC，纯 Dart，双端行为一致
- **ChangeNotifier**：当前状态管理方案；`core/` 保持纯 Dart，可被纯 Dart 单测覆盖
- **lib/ui/theme.dart**：设计变量与状态语义的唯一来源，页面不散落硬编码色值
- 计划启用（当前未加入依赖）：drift / sqlite、flutter_foreground_task、flutter_inappwebview、
  flutter_local_notifications、tray_manager

---

## 路线图

- [x] 协议逆向与验证（登录 / 课程 / 章节 / 视频进度）
- [x] 双端可行性评估与技术选型
- [x] 工程骨架与核心算法（crypto / api / models）
- [x] 双端平台工程、依赖锁定与 CI 基础
- [x] M1：登录 / 课程 / 章节只读工作台与界面设计系统
- [ ] M2：任务编排接线与日志面板
- [ ] 章节测验与作业作答
- [ ] 签到监听与通知
- [ ] Windows 端打包与自动更新

详细计划见 [docs/02-开发流程.md](docs/02-开发流程.md)。

---

## 使用须知

- 仅用于**你自己的账号**与你自己已选修的课程。
- 自动化行为可能触发平台风控（进度清空、需要人脸抽检、限制登录），这些不是 bug，是平台设计。
- 题库答案来自第三方或自有模型，**准确率不做保证**；提交前请核对。
- 考试相关功能只提供提醒与题目搬运，**不提供自动交卷**——考试有双机位、人脸抓拍和切屏检测，
  自动化的收益远小于风险。

## License

MIT

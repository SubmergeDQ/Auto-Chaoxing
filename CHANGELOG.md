# CHANGELOG

## 0.2.0 — 2026-11-12

M1 落地：仓库第一次成为可编译、可运行、可测试的 Flutter 双端工程。

### 新增

- **工程基础**：完善 `.gitignore`；用临时目录 `flutter create` 补齐 `android/`、`windows/`、`.metadata`，
  不覆盖已有代码与文档；补 `main/AndroidManifest.xml` 的 `INTERNET` 权限（模板只在 debug/profile 声明，
  release 会断网）；统一应用显示名与窗口标题；保留 gradlew 与 wrapper 供 CI 复现构建。
- **界面设计系统**：`lib/ui/theme.dart` 作为设计变量单一来源，沿用原有品牌色 `#2E7D6F`；
  新增 `widgets.dart`（状态徽章、卡片、空态、错误态、指标、账号标记、单行顶栏）、
  `app_shell.dart`（宽屏侧栏 / 窄屏底栏）、`courses_page.dart`（课程工作台 + 登录对话框）、
  `chapter_view.dart`（章节伴随面板 / 下钻页）、`aux_pages.dart`（协议自检、设置）。
  宽屏为「课程列表 / 章节详情」主从双栏，窄屏为列表 + 下钻。
- **状态与协议**：新增 `lib/state/app_state.dart`（ChangeNotifier，可注入 api）；重写 `main.dart`；
  `ChaoxingApi` 补 `fetchChapters()`，打通「登录 → 课程 → 章节 → 任务点」只读链路。
  任务点按展开懒加载，不显示未经平台确认的「已完成」状态。
- **测试与视觉取证**：新增 `app_state_test.dart`、`ui_states_test.dart`、
  可注入的 `test/support/fake_api.dart`，连同原有 `crypto_test.dart` 共 **20 项测试**；
  新增 `test/visual_capture.dart`，用 golden 导出 7 张 `1440×900` / `390×844` 视口截图，
  并在测试环境注入中文字体与 MaterialIcons（正式包不受影响）。截图作为过程文件不入库。

### 修复

- `pubspec.yaml` 的 10 个 `any` 依赖回填 caret 精确版本，提交 `pubspec.lock` 作为可复现基准。
- `ChaoxingApi` 构造函数误用 `CookieJar?` 参数（改用已保证非空的字段 `this.cookieJar`）。
- `TaskLog.toString` 多余的插值花括号；`pub get` 自动补上的 analyzer 平台目录排除。

### 评审

- 视觉盲审 **8/10**，另做一轮**静态 UX 走查**（无真实页面，未实际操作，不代表功能已走通）。
- 按反馈修订：自检页移除 `core/…` / `docs/…` 等开发者排障文案；未登录态收敛为单一主角；
  桌面课程卡去掉下钻箭头改「当前查看」；指标区改开放布局；提高次要文字对比度、
  修正中文孤字断行与示例数据口径；补移动端下钻页与设置页证据图。

### 已知限制

- **M2 自动执行尚未接线**：`TaskRunner` 已实现，但界面只有只读视图，不会自动完成任何任务点。
- 登录、章节、任务点为真实 API 调用，但**未用真实账号端到端验证**；截图全部使用示例数据。
- 平台能力（前台服务、内嵌浏览器、通知、托盘）仍是占位实现，`UnimplementedXxx` 会显式抛错。
- 本机项目路径含中文时 `flutter analyze` 的 analysis server 会崩（复制到 ASCII 路径可正常分析）；
  本机 `HTTP_PROXY` 会让 `flutter test` 的本地 WebSocket 握手失败，运行时需清空代理。
  CI 的 Linux runner 不受这两项影响，但 **CI 仍未在 GitHub Actions 上实际跑过**。
- Windows 桌面构建依赖本机 VS 2022 C++ 工具链；当前环境 `flutter doctor` 的 Windows / VS 检查
  依赖 `reg.exe` / `wmic.exe`，被沙箱策略阻止，因此**未验证 Windows 产物**。
- 动效只有静态截图证据，**正常速度下的手感未验证**。

---

## 0.1.0 — 2026-11-12

首个设计稿与工程骨架。

### 新增

- 协议逆向与可行性文档：
  - `docs/01-架构设计.md`（分层、状态机、存储、可观测）
  - `docs/02-开发流程.md`（环境、里程碑、分支规范、CI、发布、验收清单）
  - `docs/03-协议与接口.md`（登录/课程/章节/视频/作业/签到，标注已验证与待实测）
  - `docs/04-难点与注意事项.md`（技术难点 + 15 条注意事项）
  - `docs/05-Flutter双端可行性评估.md`（平台差异矩阵、选型、工期增量、退出信号）
- Flutter 工程骨架：
  - `lib/core/crypto.dart`：AES-CBC 登录加密、MD5 进度签名
  - `lib/core/chaoxing_api.dart`：登录、课程、章节卡片、视频状态与进度上报
  - `lib/core/task_runner.dart`：串行队列、节流、失败归类、状态机
  - `lib/core/models.dart`：结果类型与协议模型
  - `lib/platform/platform_services.dart`：平台能力抽象
  - `lib/main.dart`：三页壳 + 协议自检页
- `test/crypto_test.dart`：与 Python 参考实现对齐的固定向量
- `.github/workflows/ci.yml`：analyze/test + 双端构建

### 已知限制

- 作业提交接口尚未实测，Android 端计划走隐藏 WebView，Windows 端为实验性 HTTP。
- 平台能力（前台服务、内嵌浏览器、通知）仍是占位实现，`UnimplementedXxx` 会显式抛错。
- CI 为初版，尚未在本仓库实际运行过。

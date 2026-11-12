# CHANGELOG

## 0.3.0 — 2026-11-12

M2-a 落地：`TaskRunner` 第一次真正接进界面，「执行本章视频 → 实时进度与日志 → 停止 / 重跑」这条链路打通。
任务点仍然只读，执行只从章节底部发起，本地结论不冒充平台状态。

### 新增

- **任务编排加固**（`lib/core/task_runner.dart`）
  - 可注入延时（`sleep`）：测试用零延时，正式跑用真实计时，不再为等秒数写慢用例
  - 登录失效（`authExpired`）与章节未开放（`locked`）统一归 `needsAttention` 并**立即终止**；
    此前 `authExpired` 会被当成单点失败继续往下跑，白白刷一整章
  - 主动停止（`stopped`）不再计入「未通过」，返回独立的 `TaskPhase.stopped`
  - 日志分级：`通过：xxx`（info）、`已上报 5:00 / 10:00`（trace）、`未通过：xxx`（warn）、异常（error）
  - 时长统一写成 `m:ss`；汇总改为 `x / y 个任务点已通过`
  - 任务点之间保留 2 秒间隔，单账号严格串行
- **执行会话**（`lib/state/run_controller.dart`）：持有 `TaskRunner`、进度、日志（上限 400 条）、
  课程名 / 章节名 / 起止时间，对外给 `start / rerun / stop / clearLogs / reset`；
  用会话令牌丢弃 `reset` 之后迟到的回调；`AppState` 增加 `run` 字段并在 `signOut` 时 `reset`
- **任务执行页**（`lib/ui/run_console.dart`）：状态卡（阶段徽章 + 进度条 + 原因横幅 + 主动作）
  与日志控制台（三级配色、自动跟到底部、保留条数提示）；章节底部的「执行本章视频」带二次确认，
  写明范围、耗时量级与不做的事
- **导航接入**：底栏 / 侧栏新增「任务执行」；运行中在侧栏图标与窄屏底栏打点，宽屏非执行页时顶栏显示「运行中」
- **测试**：新增 `task_runner_test.dart`（7 项）、`run_controller_test.dart`（7 项），
  `ui_states_test.dart` 补 6 项执行页交互；`test/support/fake_api.dart` 补 `videoStatus` / `reportProgress`、
  上报闸门（`reportGate`）、登录失效注入与调用计数。合计 **40 项**
- **视觉取证**：18 → **26 张**，新增执行页空态 / 运行中 / 本次执行完成 / 需要人工 / 部分未通过 / 执行中禁用清空，
  以及执行确认框与移动端执行页

### 修复

- 执行页进度行原本两端分散对齐，改为单行 `已通过 1 / 2 · 正在上报 xxx`
- trace 级日志颜色过浅，按对比度门槛提亮
- 宽屏执行页顶栏「运行中」与状态卡徽章重复，改为只在非执行页显示
- 章节卡右上角「只读视图」表意不准（改成可执行后仍挂这个标记会误导），改为「进度由平台判定」
- 窄屏从执行页返回课程时栈里残留旧章节页，改为 `popUntil(isFirst)` 再切页

### 评审

- 派独立视觉评审（按 `DESIGN.md` 标准，不打分），收到 12 条按影响排序的问题，逐条处理：
  完成态不再宣称「已完成」→「本次执行完成」；失败 / 需人工态补原因横幅；执行中禁止清空日志；
  「停止执行」由失败红改中性描边；「清空日志」降为灰色文字按钮；确认框补范围与耗时预期；
  空态文案统一；日志单位改 `m:ss`
- 规范同步：`DESIGN.md` 新增「执行页与日志控制台」一节与「状态与判定口径」，状态语义由五类补为六类（新增已停止）
- 仍如实标注：动效正常速度手感、真实账号端到端流程均未验证

### 已知限制

- **只能执行视频任务点**：文档 / 阅读、章节测验、作业、签到仍未接线。
- **没有断点续跑**：`VideoStatus` 只拿到 `duration` 与 `dtoken`，拿不到平台已有进度，
  因此每次都从 0 开始重走；重复执行会把已通过的任务点再跑一遍（平台侧不会重复计，但白花时间）。
- **没有后台保活**：切到后台可能被系统挂起，执行期间需要把应用留在前台。
- 执行链路**未用真实账号端到端验证**，全部行为由 `FakeChaoxingApi` 覆盖；截图使用示例数据。
- **未验证 Windows 产物与 CI**：`flutter doctor` 的 Windows / VS 检查依赖 `reg.exe` / `wmic.exe`，
  当前环境被沙箱拦截；CI 也仍没在 GitHub Actions 上实际跑过（同 0.2.0，未变化）。

---

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
  新增 `test/visual_capture.dart`，用 golden 导出 18 张 `1440×900` / `390×844` 截图，
  覆盖常态、登录 / 断开连接等交互态，以及加载中 / 读取失败 / 章节未开放等异常态，
  并在测试环境注入中文字体与 MaterialIcons（正式包不受影响）。截图作为过程文件不入库。

### 修复

- `pubspec.yaml` 的 10 个 `any` 依赖回填 caret 精确版本，提交 `pubspec.lock` 作为可复现基准。
- `ChaoxingApi` 构造函数误用 `CookieJar?` 参数（改用已保证非空的字段 `this.cookieJar`）。
- `TaskLog.toString` 多余的插值花括号；`pub get` 自动补上的 analyzer 平台目录排除。

### 评审

- 首轮：视觉盲审 **8/10**，另做一轮**静态 UX 走查**（无真实页面，未实际操作，不代表功能已走通）。
- 首轮修订：自检页移除 `core/…` / `docs/…` 等开发者排障文案；未登录态收敛为单一主角；
  桌面课程卡去掉下钻箭头改「当前查看」；指标区改开放布局；提高次要文字对比度、
  修正中文孤字断行与示例数据口径；补移动端下钻页与设置页证据图。
- 第二轮（深度打磨复核）：视觉复核确认首轮 6 项中 4 项已解决、动效仍未验证；
  UX 复核确认 3 条关键问题已修并指出新的可复现问题。据此修订：失败 / 加载态不再显示确定
  的数字 0；状态占位统一为开放居中布局、右上「只读视图」固定不被加载态顶替；
  桌面补「点击课程」的可点线索；断开连接后在设置页可就地重新连接；补移动端章节展开态证据；
  PASS 改中文「通过」、副标题改用户口吻、修掉移动端孤字断行。`DESIGN.md` 正式落盘并补充
  状态占位规则。
- 仍如实标注：动效正常速度手感、真实账号端到端流程、移动端部分异常态均未验证。

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

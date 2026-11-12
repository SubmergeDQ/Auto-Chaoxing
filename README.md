# Auto-Chaoxing

跨平台（Android / Windows）的**学习通课程自动化客户端**。

不依赖任何宿主 App、不需要 root、不需要无障碍服务：直接复刻学习通网页端协议，
在本地完成「章节任务点、视频进度、章节测验、作业、签到监听」这些重复劳动，
并用原生 UI 把进度、日志和结果摊开给你看。

> 本项目是**设计与骨架阶段**的仓库：协议已逆向验证（见 `docs/03-协议与接口.md`），
> Flutter 工程骨架与核心算法已落地，UI 与平台能力仍在开发中。

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
| 账号登录（密码 AES-CBC） | ✅ | ✅ | 验证码/二次验证时转内嵌浏览器 |
| 课程 / 章节树 | ✅ | ✅ | `backclazzdata` + `knowledge/cards` |
| 视频任务点自动完成 | ✅ | ✅ | 伪造进度上报，串行 + 节流 |
| 文档 / 阅读任务点 | ✅ | ✅ | 停留上报 |
| 章节测验自动作答 | 🚧 | 🚧 | 题目解析 + 题库 + 提交 |
| 作业自动作答与提交 | 🚧 | ⚠️ | Windows 走纯 HTTP，Android 用隐藏 WebView 保真 |
| 签到监听 + 通知 | ✅ | ➖ | Windows 无「手机签到」语义，仅保留手动签到 |
| 考试提醒 | ✅ | ✅ | 只提醒，不自动交卷 |
| 账号隔离 / 多账号 | ✅ | ✅ | 每账号独立 cookie 与数据目录 |

图例：✅ 计划内、🚧 开发中、⚠️ 降级实现、➖ 不适用

---

## 快速开始

```bash
# 需要 Flutter 3.24+ / Dart 3.5+
flutter pub get
flutter run -d windows      # Windows 桌面
flutter run -d android      # Android 真机/模拟器
```

当前可执行的协议自检（不需要 App，验证学习通协议是否还有效）：

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
  main.dart                 # 应用入口与导航壳
  core/
    crypto.dart             # AES-CBC / MD5 / 进度签名
    chaoxing_api.dart       # 学习通 HTTP 客户端（登录、课程、章节、视频）
    models.dart             # 数据模型
    task_runner.dart        # 任务编排（串行队列、节流、断点续跑）
  platform/
    platform_services.dart  # 平台差异抽象（后台服务 / WebView / 通知 / 托盘）
docs/
  01-架构设计.md
  02-开发流程.md
  03-协议与接口.md
  04-难点与注意事项.md
  05-Flutter双端可行性评估.md
core/                       # 纯 Python 协议验证脚本（不含 App 依赖）
test/                       # 签名与加密的固定向量单测
```

---

## 技术栈

- **Flutter 3.24+ / Dart 3.5**，单代码库双端，Material 3 自适应布局
- **dio + cookie_jar**：自管 CookieJar，不依赖平台 WebView 的会话
- **pointycastle**：AES-CBC，纯 Dart，双端行为一致
- **drift / sqlite**：本地任务、日志、答案缓存
- **flutter_foreground_task**：Android 前台服务（长任务保活）
- **flutter_inappwebview**：Android 端登录与作业提交（页面自带隐藏字段，保真度优先）

---

## 路线图

- [x] 协议逆向与验证（登录 / 课程 / 章节 / 视频进度）
- [x] 双端可行性评估与技术选型
- [x] 工程骨架与核心算法（crypto / api / models）
- [ ] 任务编排与日志面板
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

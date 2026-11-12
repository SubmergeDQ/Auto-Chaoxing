# CHANGELOG

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

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 单实例：双击快捷方式时不再开第二个窗口。
  // `Local\` 限定在当前登录会话，不同 Windows 用户互不干扰。
  // 互斥量随进程退出由系统释放，不需要额外清理文件。
  HANDLE instance_mutex =
      ::CreateMutex(nullptr, TRUE, L"Local\\Auto-Chaoxing-Single-Instance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // 已有实例可能还在启动中，短暂重试几次再放弃。
    HWND existing = nullptr;
    for (int i = 0; i < 30 && existing == nullptr; ++i) {
      existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
      if (existing == nullptr) {
        ::Sleep(100);
      }
    }
    if (existing != nullptr) {
      // 窗口可能被最小化或收到托盘（隐藏），两种都要拉回可见状态。
      ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // 1280 宽刚好越过 1000 的宽屏断点，默认就以「侧栏 + 主从双栏」打开；
  // 高度给到 820，课程页的指标行 + 列表不用一进来就滚动。
  Win32Window::Size size(1280, 820);
  if (!window.Create(L"Auto-Chaoxing · 学习通客户端", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

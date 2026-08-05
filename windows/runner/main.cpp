#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const wchar_t* kSoftwareRenderingSwitch = L"--enable-software-rendering";
  const wchar_t* kSerialGcSwitch = L"--enable-serial-gc";
  const wchar_t* kLiteSwitch = L"--lite";

  std::wstring full_command_line = ::GetCommandLineW();
  if (full_command_line.find(kSoftwareRenderingSwitch) == std::wstring::npos) {
    std::wstring relaunch_command = full_command_line;
    relaunch_command.append(L" ");
    relaunch_command.append(kSoftwareRenderingSwitch);
    relaunch_command.append(L" ");
    relaunch_command.append(kSerialGcSwitch);
    relaunch_command.append(L" ");
    relaunch_command.append(kLiteSwitch);

    STARTUPINFOW startup_info = {};
    startup_info.cb = sizeof(startup_info);
    PROCESS_INFORMATION process_info = {};
    std::wstring mutable_command = relaunch_command;
    if (::CreateProcessW(nullptr, &mutable_command[0], nullptr, nullptr, FALSE, 0,
                         nullptr, nullptr, &startup_info, &process_info)) {
      ::CloseHandle(process_info.hThread);
      ::CloseHandle(process_info.hProcess);
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_gpu_preference(flutter::GpuPreference::LowPowerPreference);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  std::vector<std::string> dart_entrypoint_arguments;
  dart_entrypoint_arguments.reserve(command_line_arguments.size());
  for (const auto& arg : command_line_arguments) {
    if (arg == "--enable-software-rendering" || arg == "--enable-serial-gc") {
      continue;
    }
    dart_entrypoint_arguments.push_back(arg);
  }
  project.set_dart_entrypoint_arguments(std::move(dart_entrypoint_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1024, 640);
  if (!window.Create(L"ordimed", origin, size)) {
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

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The class and title the runner creates its window with. Together they are
// how a second copy of the app finds the first.
constexpr wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"HozaSend";
constexpr wchar_t kInstanceMutex[] = L"HozaSend.SingleInstance";

// The files this process was started with, one per line.
//
// Windows starts the app afresh for "Send to HozaSend" and for "Open with",
// passing the file as an argument - and for a multi-selection it starts one
// copy per file. Only things that exist on disk are kept: the command line
// also carries switches, and a debug run adds its own.
std::wstring SharedPathsFromCommandLine() {
  int count = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &count);
  if (argv == nullptr) {
    return std::wstring();
  }
  std::wstring joined;
  for (int i = 1; i < count; ++i) {
    if (argv[i] == nullptr || argv[i][0] == L'-') {
      continue;
    }
    if (::GetFileAttributesW(argv[i]) == INVALID_FILE_ATTRIBUTES) {
      continue;
    }
    if (!joined.empty()) {
      joined.push_back(L'\n');
    }
    joined.append(argv[i]);
  }
  ::LocalFree(argv);
  return joined;
}

// Hands them to the copy of HozaSend already running.
//
// That copy may still be starting: Explorer runs one process per file for a
// multi-selection, so several of these can race the window into existence -
// hence a wait rather than a single look.
void ForwardToRunningInstance(const std::wstring& joined) {
  if (joined.empty()) {
    return;
  }
  for (int attempt = 0; attempt < 150; ++attempt) {
    HWND window = ::FindWindowW(kWindowClass, kWindowTitle);
    if (window != nullptr) {
      COPYDATASTRUCT payload{};
      payload.dwData = kHozaShareMessage;
      payload.cbData = static_cast<DWORD>(joined.size() * sizeof(wchar_t));
      payload.lpData = const_cast<wchar_t*>(joined.c_str());
      ::SendMessageW(window, WM_COPYDATA, 0,
                     reinterpret_cast<LPARAM>(&payload));
      return;
    }
    ::Sleep(100);
  }
}

}  // namespace

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

  // One copy of HozaSend at a time. A second could not receive anything anyway
  // - the first holds the discovery and transfer ports - so the files it was
  // started with are handed to the running window instead. That is what makes
  // "Send to HozaSend" add to the queue rather than open a dead second window.
  HANDLE instance_lock = ::CreateMutexW(nullptr, TRUE, kInstanceMutex);
  if (instance_lock != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ForwardToRunningInstance(SharedPathsFromCommandLine());
    ::CloseHandle(instance_lock);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Taller than it is wide relative to the default: HozaSend is a single
  // column of cards, so extra height shows more devices while extra width
  // would only pad the margins.
  Win32Window::Size size(1120, 820);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (instance_lock != nullptr) {
    ::ReleaseMutex(instance_lock);
    ::CloseHandle(instance_lock);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}

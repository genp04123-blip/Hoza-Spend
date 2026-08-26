#include "flutter_window.h"

#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

// Splits the block a second copy of the app sent over: the paths it was
// started with, one per line, as UTF-16.
std::vector<std::string> SplitPaths(const wchar_t* data, size_t length) {
  std::vector<std::string> paths;
  std::wstring joined(data, length);
  size_t start = 0;
  while (start < joined.size()) {
    size_t end = joined.find(L'\n', start);
    if (end == std::wstring::npos) {
      end = joined.size();
    }
    std::wstring one = joined.substr(start, end - start);
    if (!one.empty()) {
      paths.push_back(Utf8FromUtf16(one.c_str()));
    }
    start = end + 1;
  }
  return paths;
}

flutter::EncodableValue AsList(const std::vector<std::string>& paths) {
  flutter::EncodableList shared;
  for (const std::string& path : paths) {
    shared.push_back(flutter::EncodableValue(path));
  }
  return flutter::EncodableValue(shared);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Files sent here by "Send to", by "Open with", or by a drop on the exe
  // while the app was already running. Dart pulls whatever is waiting as it
  // starts, and is pushed anything that lands afterwards.
  share_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "hozasend/share",
          &flutter::StandardMethodCodec::GetInstance());
  share_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "consume") {
          result->NotImplemented();
          return;
        }
        dart_listening_ = true;
        flutter::EncodableValue shared = AsList(pending_shares_);
        pending_shares_.clear();
        result->Success(shared);
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    share_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::DeliverShare(std::vector<std::string> paths) {
  if (paths.empty()) {
    return;
  }
  // Held rather than sent while Dart is still starting. The app is very often
  // being launched by this very share, so this is the ordinary case rather
  // than the edge one.
  if (!dart_listening_ || !share_channel_) {
    pending_shares_.insert(pending_shares_.end(), paths.begin(), paths.end());
    return;
  }
  share_channel_->InvokeMethod(
      "shared", std::make_unique<flutter::EncodableValue>(AsList(paths)));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      // A second copy of HozaSend, started by "Send to" or "Open with",
      // handing over its files before it exits.
      auto* payload = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (payload == nullptr || payload->dwData != kHozaShareMessage ||
          payload->cbData == 0 || payload->lpData == nullptr) {
        break;
      }
      DeliverShare(SplitPaths(reinterpret_cast<const wchar_t*>(payload->lpData),
                              payload->cbData / sizeof(wchar_t)));
      // The user just sent files to this window; it should be the window they
      // are looking at.
      if (::IsIconic(hwnd)) {
        ::ShowWindow(hwnd, SW_RESTORE);
      }
      ::SetForegroundWindow(hwnd);
      return TRUE;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

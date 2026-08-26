#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// Marks a WM_COPYDATA block as HozaSend handing over shared files, rather than
// some other process talking to a window it happened to find. Sent by a second
// copy of the app started by "Send to" or "Open with" while this one is
// already running.
constexpr ULONG_PTR kHozaShareMessage = 0x484F5A41;  // 'HOZA'

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Hands |paths| to Dart, or holds them until Dart is listening. Files can
  // arrive before the engine has run a line of Dart - a share is what starts
  // the app in the first place - so they are never simply dropped.
  void DeliverShare(std::vector<std::string> paths);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Carries shared files to Dart. Matched in share_intake_service.dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      share_channel_;

  // Shares that arrived before Dart asked for them.
  std::vector<std::string> pending_shares_;

  // True once Dart has asked for the pending shares, which is the only proof
  // that its end of the channel exists. Until then a push would be sent into a
  // channel with no handler and lost.
  bool dart_listening_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
